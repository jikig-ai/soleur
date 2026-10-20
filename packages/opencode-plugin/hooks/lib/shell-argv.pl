#!/usr/bin/env perl
# shell-argv.pl — the shell lexer behind the destructive-command guard (W2, #9601).
#
# QUESTION ANSWERED: which simple commands would bash EXECUTE from one Bash tool command
# string, and what is each one's argv? The guard decides on those argv records, never on the
# raw text: bash runs `"$(terraform destroy)"`, `bash -c "terraform destroy"` and
# `r""m -rf ~` although their text does not read as the command, and it does NOT run the
# text in `echo "terraform destroy"` or a heredoc body.
#
# PROVENANCE. The lexer is vendored from .claude/hooks/lib/filing-shape.pl (ADR-256, the
# repo-local lexer behind the guardrails filing gate; `.claude/hooks/lib/` never ships to
# customers, the plugin does). Three spans of this file, delimited by full-line comment
# markers named SHARED-LEXER (one BEGIN and one END per span), are BYTE-IDENTICAL to the same
# spans there: the lexer constants, the lexer state with its helper subs, and the lexer proper
# (`lex_string` through `runner_script`). A test enforces it: plugins/soleur/test/
# shell-argv-parity.test.sh requires exactly three spans per file, each above a minimum size,
# byte identity of every span, and equal argv traces on a grammar corpus. Fix a lexing bug in
# BOTH files, inside the spans; everything outside the spans (`process_command` and the entry
# below) is this file's own. Two declarations inside span 1 (`%FIND_ACT`, `$MAX_RECORDS`) are
# inert here: only the filing lexer reads them, and they stay because the span is identical.
#
# GRAMMAR (see filing-shape.pl for the full model): script := command (SEP command)*; SEP is
# newline ; & | && || |& ;; ;& ;;& ( ); blanks are space and tab only; quoting, $'..',
# $(..), `..`, <(..), ${..}, $((..)), comments (a `#` at the start of a word only), heredocs
# (a quoted delimiter makes the body data) and `case` patterns are modelled; `bash|sh|zsh|
# dash|ksh -c STRING` and `eval STRING` are lexed again as their own scripts (ctx `shell-c`
# and `eval`). Every simple command appears EXACTLY ONCE in the output, including one inside
# a substitution that the lexer reads twice. Everything else that runs a string (xargs,
# find -exec, ssh, a script written then run) is a non-goal.
#
# DEPENDENCIES AND PORTABILITY. perl >= 5.10 and its core pragmas only: no CPAN module, no
# GNU-only option, no bash-4 feature. It reads stdin and writes stdout and stderr; it touches
# no file and no network.
#
# USAGE.  perl shell-argv.pl [--trace] < command-text
#   stdin: the raw command bytes (may contain newlines; a NUL byte is rejected, exit 2).
#   --trace: also print, on stderr, one line per simple command, `<ctx path>: [w1] [w2] …`
#   (all words, including leading reserved words); use it from a FILE (`… --trace < cmd.txt`),
#   never by pasting a command into a double-quoted argument, which would run its substitutions.
#
# OUTPUT CONTRACT (the hook parses this; parse BY COUNT, never by searching for `C` or `OK`).
# stdout is a sequence of NUL-terminated fields, every field terminated by exactly one \0:
#   success, exit 0:   record* then the field OK
#       record := C \0 <ctx> \0 <argc> \0 ( <flags> \0 <arg> \0 ){argc}
#     C        literal field `C`.
#     <ctx>    where the command sits: top, subst ($(..) <(..) >(..) ${ ..; }), backtick,
#              heredoc (inside an unquoted heredoc body), shell-c, eval; for a nested
#              command the innermost context.
#     <argc>   decimal count of words that follow (>= 1).
#     <flags>  per word, a non-empty string: `-` (neither), `q` (some part of the word was
#              quoted or backslash-escaped), `x` (some part is an expansion: $VAR, $(..),
#              `..`, ${..}, $((..)), <(..)), or `qx`. `~` is NOT expanded here: the hook
#              treats a word as a tilde candidate only when it starts with `~` and carries
#              no `q`, so `'~'` and `"~"` are literals. `$VAR` text is kept raw in <arg>.
#     <arg>    the word's dequoted text, expansions left as their source text. Newlines may
#              occur; NUL never does (a NUL produced by `$'\0'` is dropped).
#     Leading unquoted reserved words (! { then do else elif if while until time) are
#     removed from the record; a command that is only reserved words yields no record.
#     Leading `NAME=value` assignments and wrappers (sudo, env, timeout, …) are NOT removed:
#     the hook's rule table unwraps them.
#     Record order is the lexer's emission order: a command's substitutions precede it
#     (`echo $(a; b)` gives a, b, echo); `a && b` gives a, b. There is no record cap.
#   failure, exit 2 or 3:  the two fields  E \0 <cause> \0   and nothing else; stderr carries
#     `bound=<cause>`. Exit 2 = the input is not parseable shell (unbalanced quote,
#     unterminated substitution, missing heredoc delimiter word, NUL byte). Exit 3 = a bound
#     tripped (cause `depth` > 16 nested substitutions, `budget` = 8*input + 64 KiB of work
#     and output, `alarm` after 2 s) or the lexer died (`crash`). The hook must treat both
#     as "could not parse": ask, never allow.
# A run that prints neither OK nor E (killed, no perl) is also "could not parse".
use strict;
BEGIN { $^W = 1 }

# ---- lexer constants (shared) -------------------------------------------------------
# BEGIN SHARED-LEXER
my %RUNNER     = map { $_ => 1 } qw(bash sh zsh dash ksh);
my %FIND_ACT   = map { $_ => 1 } qw(-exec -execdir -ok -okdir);
my %RESERVED   = map { $_ => 1 } qw(! { then do else elif if while until time);

my $MAX_DEPTH   = 16;
my $MAX_RECORDS = 32;
my $ALARM_S     = 2;
# END SHARED-LEXER

# ---- lexer state and helpers (shared) -----------------------------------------------
# BEGIN SHARED-LEXER
my ($BUDGET, $USED, $DEPTH, $INVIS, $RELEX) = (0, 0, 0, 0, 0);
my (@RECORDS, @HD_LOG, @PATH, %SEEN_SUBST, %SEEN_STR, %VARS);
my $TRACE = 0;

sub fail2 { die { code => 2, cause => 'exit2', detail => $_[0] } }
sub fail3 { die { code => 3, cause => $_[0] } }
sub charge { $USED += $_[0]; fail3('budget') if $USED > $BUDGET }
sub enter  { fail3('depth') if ++$DEPTH > $MAX_DEPTH }
sub leave  { $DEPTH-- }
sub at_end { my $sr = shift; (pos($$sr) // 0) >= length $$sr }
sub peek   { my ($sr, $n) = @_; substr($$sr, pos($$sr) // 0, $n // 1) }
sub new_state { my $t = shift; my $st = { s => \$t, hq => [] }; pos(${ $st->{s} }) = 0; $st }
sub basename_of { my $b = shift; $b =~ s{.*/}{}s; $b }
sub new_word { { t => '', lit => '', x => 0, q => 0, hd => [] } }
# END SHARED-LEXER

# ---- lexer (shared) -----------------------------------------------------------------
# BEGIN SHARED-LEXER
sub lex_string {
  my ($text, $ctx) = @_;
  return if $SEEN_STR{$text}++;          # memoized: a string is lexed once
  charge(length $text);
  my $st = new_state($text);
  push @PATH, $ctx;
  $INVIS++; $RELEX++;
  parse_list($st, $ctx, 'eof');
  drain_heredocs($st);
  $INVIS--; $RELEX--;
  pop @PATH;
}

sub reserved { !$_[0]{q} && $RESERVED{ $_[0]{t} } }

sub parse_list {
  my ($st, $ctx, $term) = @_;
  enter();
  my $sr = $st->{s};
  my @words;
  my $parens = 0;
  my @case;                               # subj | pat | body, innermost last
  my $cmd = {};
  my $cmdpos = 1;                         # every word so far is a reserved word
  my $flush = sub {
    process_command([@words], $ctx, $cmd) if @words;
    @words = ();
    $cmd = {};
    $cmdpos = 1;
  };
  while (1) {
    if ($$sr =~ /\G[ \t]+/gc) { next }
    if ($$sr =~ /\G\\\n/gc) { next }
    if (at_end($sr)) {
      $flush->();
      fail2('unterminated $( or ${') if $term ne 'eof';
      last;
    }
    my $p0 = pos($$sr);
    if ($$sr =~ /\G\n/gc) {
      charge(1);
      $flush->() unless @case && $case[-1] eq 'pat';
      drain_heredocs($st);
      next;
    }
    if ($$sr =~ /\G#[^\n]*/gc) { charge(pos($$sr) - $p0); next }
    if ($term eq '}' && $cmdpos && $$sr =~ /\G\}(?=[\s;&|)<>]|\z)/gc) {
      charge(1); $flush->(); leave(); return;
    }
    if ($cmdpos || (@words && !$words[-1]{q} && $words[-1]{t} eq 'for')) {
      if (peek($sr, 2) eq '((') {
        my $n0 = @RECORDS;
        pos($$sr) = $p0 + 2;
        next if scan_arith($st, $ctx);
        splice @RECORDS, $n0;            # not arithmetic: two subshells
        pos($$sr) = $p0;
      }
    }
    if (peek($sr, 2) =~ /^[<>]\(/) { push @words, parse_word($st, $ctx); next }
    if ($$sr =~ /\G(?:\d+|\{[A-Za-z_][A-Za-z0-9_]*\})?(<<<|<<-|<<|&>>|&>|>>|>\||>&|<&|<>|>|<)/gc) {
      my $op = $1;
      charge(pos($$sr) - $p0);
      $$sr =~ /\G[ \t]+/gc;
      if ($op eq '<<' || $op eq '<<-') {
        fail2('missing heredoc delimiter') if at_end($sr) || peek($sr) =~ /[\n;&|()<>]/;
        my $w = parse_word($st, $ctx);
        push @{ $st->{hq} }, { delim => $w->{t}, quoted => $w->{q}, strip => $op eq '<<-', cmd => $cmd };
      } elsif (!at_end($sr) && peek($sr) !~ /[\n;&|()<>]/) {
        parse_word($st, $ctx);            # target dropped; its substitutions lexed
      }
      next;
    }
    if ($$sr =~ /\G(;;&|;;|;&)/gc) {
      charge(length $1);
      $flush->();
      $case[-1] = 'pat' if @case && $case[-1] eq 'body';
      next;
    }
    if ($$sr =~ /\G(?:;|&&|\|\||\|&|\||&)/gc) {
      charge(pos($$sr) - $p0);
      next if @case && $case[-1] eq 'pat';  # `a|b)` pattern alternation
      $flush->();
      next;
    }
    if ($$sr =~ /\G\(/gc) {
      charge(1);
      next if @case && $case[-1] eq 'pat';  # optional `(` before a pattern
      $parens++; $flush->(); next;
    }
    if ($$sr =~ /\G\)/gc) {
      charge(1);
      if (@case && $case[-1] eq 'pat') { @words = (); $cmdpos = 1; $case[-1] = 'body'; next }
      $flush->();
      if ($parens > 0) { $parens--; next }
      if ($term eq ')') { leave(); return }
      next;                               # a stray ) is a separator
    }
    my $w = parse_word($st, $ctx);
    my $at_cmdpos = $cmdpos;
    push @words, $w;
    $cmdpos = 0 unless reserved($w);
    my $kw = $w->{q} ? '' : $w->{t};
    if ($kw eq 'case' && $at_cmdpos) { push @case, 'subj' }
    elsif (@case && $case[-1] eq 'subj' && $kw eq 'in') { $case[-1] = 'pat'; @words = (); $cmdpos = 1 }
    elsif (@case && $case[-1] eq 'pat' && $kw eq 'esac') { pop @case; @words = (); $cmdpos = 1 }
    elsif (@case && $case[-1] eq 'body' && $kw eq 'esac' && $at_cmdpos) { pop @case; @words = (); $cmdpos = 1 }
  }
  leave();
}

# One shell word. Returns { t => dequoted text (expansions kept as raw source),
# lit => the literal (non-expansion) text, x => contains an expansion,
# q => any quoting seen, hd => heredoc bodies drained inside it }.
sub parse_word {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $w = new_word();
  my $mark = @HD_LOG;
  while (1) {
    my $p0 = pos($$sr);
    if ($$sr =~ /\G([^ \t\n;&|()<>\\'"\$`]+)/gc) { $w->{t} .= $1; $w->{lit} .= $1; charge(length $1); next }
    last if at_end($sr);
    my $c = peek($sr);
    if ($c eq '\\') {
      if ($$sr =~ /\G\\\n/gc) { charge(2); next }
      if ($$sr =~ /\G\\(.)/gcs) { $w->{t} .= $1; $w->{lit} .= $1; $w->{q} = 1; charge(2); next }
      $$sr =~ /\G\\/gc; $w->{t} .= '\\'; $w->{lit} .= '\\'; next;
    }
    if ($c eq "'") {
      $$sr =~ /\G'([^']*)'/gc or fail2("unbalanced '");
      $w->{t} .= $1; $w->{lit} .= $1; $w->{q} = 1; charge(pos($$sr) - $p0); next;
    }
    if ($c eq '"') { $$sr =~ /\G"/gc; $w->{q} = 1; parse_dq($st, $ctx, $w); next }
    if ($c eq '$') {
      if ($$sr =~ /\G\$'((?:[^'\\]|\\.)*)'/gcs) {
        my $v = decode_ansi($1);
        $w->{t} .= $v; $w->{lit} .= $v; $w->{q} = 1; charge(pos($$sr) - $p0); next;
      }
      fail2("unbalanced \$'") if peek($sr, 2) eq "\$'";
      if (peek($sr, 2) eq '$"') { $$sr =~ /\G\$"/gc; $w->{q} = 1; parse_dq($st, $ctx, $w); next }
      dollar($st, $ctx, $w); next;
    }
    if ($c eq '`') { $w->{t} .= parse_backtick($st, $ctx, 0); $w->{x} = 1; next }
    if (peek($sr, 2) =~ /^[<>]\(/) { $w->{t} .= parse_subst($st, $ctx, 2); $w->{x} = 1; next }
    last;                                  # blank, separator, ( ) < >
  }
  $w->{hd} = [ @HD_LOG[$mark .. $#HD_LOG] ];
  return $w;
}

my %ANSI = (a => "\a", b => "\b", e => "\e", E => "\e", f => "\f", n => "\n",
  r => "\r", t => "\t", v => "\x0b", '\\' => '\\', "'" => "'", '"' => '"', '?' => '?');
sub decode_ansi {
  my $s = shift;
  $s =~ s{\\(?:([abeEfnrtv\\'"?])|x([0-9A-Fa-f]{1,2})|([0-7]{1,3})|u([0-9A-Fa-f]{1,4})|U([0-9A-Fa-f]{1,8})|c(.))}{
    defined $1 ? $ANSI{$1}
    : defined $2 ? chr(hex $2)
    : defined $3 ? chr(oct $3 & 0xff)
    : defined $4 ? chr(hex $4)
    : defined $5 ? chr(hex $5)
    : chr(ord(uc $6) & 0x1f)
  }gse;
  return $s;
}

# `$…` in a word, a double-quoted string or a heredoc body.
sub dollar {
  my ($st, $ctx, $w) = @_;
  my $sr = $st->{s};
  if (peek($sr, 3) eq '$((') { $w->{t} .= parse_arith($st, $ctx); $w->{x} = 1; return }
  if (peek($sr, 2) eq '$(')  { $w->{t} .= parse_subst($st, $ctx, 2); $w->{x} = 1; return }
  if (peek($sr, 2) eq '${')  { $w->{t} .= parse_brace($st, $ctx); $w->{x} = 1; return }
  if ($$sr =~ /\G(\$(?:[A-Za-z_][A-Za-z0-9_]*|[0-9?\$@*#!-]))/gc) {
    $w->{t} .= $1; $w->{x} = 1; charge(length $1); return;
  }
  $$sr =~ /\G\$/gc; $w->{t} .= '$'; $w->{lit} .= '$'; charge(1);
}

# After the opening `"`; consumes through the closing `"`.
sub parse_dq {
  my ($st, $ctx, $w) = @_;
  my $sr = $st->{s};
  $INVIS++;
  while (1) {
    if ($$sr =~ /\G([^"\\\$`]+)/gc) { $w->{t} .= $1; $w->{lit} .= $1; charge(length $1); next }
    fail2('unbalanced "') if at_end($sr);
    my $c = peek($sr);
    if ($c eq '"') { $$sr =~ /\G"/gc; charge(1); last }
    if ($c eq '\\') {
      if ($$sr =~ /\G\\\n/gc) { charge(2); next }
      if ($$sr =~ /\G\\([\$`"\\])/gc) { $w->{t} .= $1; $w->{lit} .= $1; charge(2); next }
      $$sr =~ /\G\\/gc; $w->{t} .= '\\'; $w->{lit} .= '\\'; charge(1); next;
    }
    if ($c eq '`') { $w->{t} .= parse_backtick($st, $ctx, 1); $w->{x} = 1; next }
    dollar($st, $ctx, $w);
  }
  $INVIS--;
}

# A substitution's records were already taken once when the same text is met
# again through a RE-LEXED runner/eval string: drop the duplicates there, and
# only there (two identical substitutions in the command are two filings).
sub dedup_after {
  my ($n0, $inner) = @_;
  splice @RECORDS, $n0 if $RELEX && $SEEN_SUBST{$inner};
  $SEEN_SUBST{$inner} = 1;
}

# `$(…)`, `<(…)`, `>(…)` — lexed in place, with their own heredoc queue.
sub parse_subst {
  my ($st, $ctx, $oplen) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  pos($$sr) = $start + $oplen;
  charge($oplen);
  my $n0 = @RECORDS;
  my $inner_ctx = $ctx eq 'heredoc' ? 'heredoc' : 'subst';
  my $outer_hq = $st->{hq};
  $st->{hq} = [];
  push @PATH, $inner_ctx;
  parse_list($st, $inner_ctx, ')');
  pop @PATH;
  $st->{hq} = $outer_hq;
  my $raw = substr($$sr, $start, pos($$sr) - $start);
  dedup_after($n0, substr($raw, $oplen, -1));
  return $raw;
}

sub parse_backtick {
  my ($st, $ctx, $in_dq) = @_;
  my $sr = $st->{s};
  my $p0 = pos($$sr);
  $$sr =~ /\G`((?:[^`\\]|\\.)*)`/gcs or fail2('unbalanced `');
  my $body = $1;
  charge(pos($$sr) - $p0);
  (my $inner = $body) =~ s/\\([\$`\\])/$1/g;
  $inner =~ s/\\"/"/g if $in_dq;
  my $n0 = @RECORDS;
  unless ($RELEX && $SEEN_SUBST{$inner}) {
    my $inner_ctx = $ctx eq 'heredoc' ? 'heredoc' : 'backtick';
    push @PATH, $inner_ctx;
    my $st2 = new_state($inner);
    parse_list($st2, $inner_ctx, 'eof');
    drain_heredocs($st2);
    pop @PATH;
  }
  dedup_after($n0, $inner);
  return substr($$sr, $p0, pos($$sr) - $p0);
}

# `${…}`: its text is never a script; substitutions inside it are. `${ cmd; }`
# and `${| cmd; }` (bash 5.3) ARE scripts, lexed like $(…).
sub parse_brace {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  if ($$sr =~ /\G\$\{\|?(?=[ \t\n])/gc) {
    charge(pos($$sr) - $start);
    my $n0 = @RECORDS;
    my $inner_ctx = $ctx eq 'heredoc' ? 'heredoc' : 'subst';
    my $outer_hq = $st->{hq};
    $st->{hq} = [];
    push @PATH, $inner_ctx;
    parse_list($st, $inner_ctx, '}');
    pop @PATH;
    $st->{hq} = $outer_hq;
    my $raw = substr($$sr, $start, pos($$sr) - $start);
    dedup_after($n0, $raw);
    return $raw;
  }
  $$sr =~ /\G\$\{/gc; charge(2);
  enter();
  my $scratch = new_word();
  while (1) {
    if ($$sr =~ /\G([^{}\$`'"\\]+)/gc) { charge(length $1); next }
    fail2('unterminated ${') if at_end($sr);
    my $c = peek($sr);
    if ($c eq '}') { $$sr =~ /\G\}/gc; charge(1); last }
    if ($c eq '{') { $$sr =~ /\G\{/gc; charge(1); next }
    if ($c eq '\\') { $$sr =~ /\G\\.?/gcs; charge(2); next }
    if ($c eq "'") {
      my $p0 = pos($$sr);
      $$sr =~ /\G'[^']*'/gc or fail2("unbalanced ' in \${");
      charge(pos($$sr) - $p0); next;
    }
    if ($c eq '"') { $$sr =~ /\G"/gc; parse_dq($st, $ctx, $scratch); next }
    if ($c eq '`') { parse_backtick($st, $ctx, 0); next }
    dollar($st, $ctx, $scratch);
  }
  leave();
  return substr($$sr, $start, pos($$sr) - $start);
}

# The body of `((…))` / `$((…))` after the opener. Returns 1 when it closes with
# `))`, 0 when it does not (the caller then re-reads it as subshells).
sub scan_arith {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  enter();
  my $d = 0;
  my $scratch = new_word();
  my $ok = 0;
  while (1) {
    if ($$sr =~ /\G([^()\$`'"\\]+)/gc) { charge(length $1); next }
    last if at_end($sr);
    my $c = peek($sr);
    if ($c eq '(') { $$sr =~ /\G\(/gc; $d++; charge(1); next }
    if ($c eq ')') {
      $$sr =~ /\G\)/gc; charge(1);
      if ($d > 0) { $d--; next }
      $ok = 1 if $$sr =~ /\G\)/gc;
      last;
    }
    if ($c eq '\\') { $$sr =~ /\G\\.?/gcs; charge(2); next }
    if ($c eq "'") {
      my $p0 = pos($$sr);
      last unless $$sr =~ /\G'[^']*'/gc;
      charge(pos($$sr) - $p0); next;
    }
    if ($c eq '"') { $$sr =~ /\G"/gc; parse_dq($st, $ctx, $scratch); next }
    if ($c eq '`') { parse_backtick($st, $ctx, 0); next }
    dollar($st, $ctx, $scratch);
  }
  leave();
  return $ok;
}

sub parse_arith {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  my $n0 = @RECORDS;
  pos($$sr) = $start + 3;
  charge(3);
  return substr($$sr, $start, pos($$sr) - $start) if scan_arith($st, $ctx);
  splice @RECORDS, $n0;                    # `$( (…) )`: a subshell in $(…)
  pos($$sr) = $start;
  return parse_subst($st, $ctx, 2);
}

# At an unquoted newline: read every pending heredoc body, in order.
sub drain_heredocs {
  my $st = shift;
  my $sr = $st->{s};
  my @q = @{ $st->{hq} };
  @{ $st->{hq} } = ();
  for my $h (@q) {
    my $body = '';
    while (!at_end($sr)) {
      $$sr =~ /\G([^\n]*)(\n?)/gc;
      my ($line, $nl) = ($1, $2);
      charge(length($line) + length($nl));
      my $cmp = $line;
      $cmp =~ s/^\t+// if $h->{strip};
      last if $cmp eq $h->{delim};
      $body .= $line . $nl;
    }
    push @HD_LOG, $body;
    push @{ $VARS{ $h->{cmd}{name} } }, $body if defined $h->{cmd}{name};
    next if $h->{quoted};
    # An unquoted delimiter: the body is expanded like a "…" string.
    enter();
    $INVIS++;
    push @PATH, 'heredoc';
    my $st2 = new_state($body);
    my $sr2 = $st2->{s};
    my $scratch = new_word();
    while (!at_end($sr2)) {
      if ($$sr2 =~ /\G([^\\\$`]+)/gc) { charge(length $1); next }
      my $c = peek($sr2);
      if ($c eq '\\') { $$sr2 =~ /\G\\.?/gcs; charge(2); next }
      if ($c eq '`') { parse_backtick($st2, 'heredoc', 0); next }
      dollar($st2, 'heredoc', $scratch);
    }
    pop @PATH;
    $INVIS--;
    leave();
  }
}

# ---- a simple command ---------------------------------------------------------
sub runner_script {
  my ($t, $k) = @_;
  my $seen_c = 0;
  my $j = $k + 1;
  while ($j < @$t) {
    my $a = $t->[$j];
    if ($a eq '--' || $a eq '-') { $j++; last }
    if ($a =~ /^--(?:rcfile|init-file)\z/) { $j += 2; next }
    if ($a =~ /^--./) { $j++; next }
    if ($a =~ /^[-+]([A-Za-z]+)\z/) {
      my $cl = $1;
      $seen_c = 1 if $a =~ /^-/ && $cl =~ /c/;
      $j += 1 + ($cl =~ tr/oO//);         # every -o/-O in a cluster takes a value
      next;
    }
    last;
  }
  return undef unless $seen_c && $j < @$t;
  return $t->[$j];
}
# END SHARED-LEXER

# ---- a simple command: one argv record (this file's own) ----------------------------
# Pushed onto @RECORDS, not printed: the lexer rolls records back with `splice @RECORDS, $n0`
# when it re-reads a substitution or a `((` that turned out to be two subshells.
sub process_command {
  my ($words, $ctx, $cmd) = @_;
  my @t = map { $_->{t} } @$words;
  print STDERR join('>', @PATH), ': ', join(' ', map { "[$_]" } @t), "\n" if $TRACE;
  my $i = 0;
  $i++ while $i < @t && !$words->[$i]{q} && $RESERVED{ $t[$i] };
  if ($i < @t) {
    my @fields;
    for my $k ($i .. $#t) {
      my $w = $words->[$k];
      my $flags = ($w->{q} ? 'q' : '') . ($w->{x} ? 'x' : '');
      $flags = '-' unless length $flags;
      (my $arg = $t[$k]) =~ tr/\0//d;      # NUL is the frame separator; bash drops it too
      push @fields, $flags, $arg;
    }
    push @RECORDS, [$ctx, scalar(@t) - $i, \@fields];
  }
  for my $k (0 .. $#t) {
    if ($RUNNER{ basename_of($t[$k]) }) {
      my $s = runner_script(\@t, $k);
      lex_string($s, 'shell-c') if defined $s;
    } elsif ($t[$k] eq 'eval') {
      lex_string(join(' ', @t[$k + 1 .. $#t]), 'eval');
      last;
    }
  }
}

# ---- entry --------------------------------------------------------------------------
$TRACE = 1 if @ARGV && $ARGV[0] eq '--trace';

binmode STDIN; binmode STDOUT;
$SIG{ALRM} = sub { print STDERR "bound=alarm\n"; print "E\0alarm\0"; exit 3 };
alarm $ALARM_S;
my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;
my $out = '';
my $ok = eval {
  fail2('NUL byte in input') if index($input, "\0") >= 0;
  $BUDGET = 8 * length($input) + 65536;
  my $st = new_state($input);
  push @PATH, 'top';
  parse_list($st, 'top', 'eof');
  drain_heredocs($st);
  pop @PATH;
  for my $r (@RECORDS) {
    my ($ctx, $argc, $f) = @$r;
    my $rec = join("\0", 'C', $ctx, $argc, @$f) . "\0";
    charge(length $rec);                  # the output is inside the budget too
    $out .= $rec;
  }
  1;
};
alarm 0;
unless ($ok) {
  my $e = $@;
  if (ref $e eq 'HASH') {
    print STDERR 'bound=', $e->{cause}, (defined $e->{detail} ? " ($e->{detail})" : ''), "\n";
    print "E\0$e->{cause}\0";
    exit $e->{code};
  }
  print STDERR "bound=crash ($e)\n";
  print "E\0crash\0";
  exit 3;
}
print $out, "OK\0";
exit 0;
