#!/usr/bin/env perl
# filing-shape.pl — the shell lexer behind the guardrails filing gate (#9089).
#
# QUESTION ANSWERED: which `gh issue create|new` and `gh api <issues collection>`
# POSTs would bash EXECUTE from one Bash tool command string, and what are each
# filing's OWN exits (milestone, repo, labels, body)? Grepping a quote-blanked
# copy of the command ($SCAN) could not answer it: bash runs `"$(gh issue create)"`,
# `bash -c "gh …"` and `gh api "repos/o/r/issues"` although their text is quoted.
#
# CONTRACTS (ADR-256):
#   * filing_shape() below and filingShape() in
#     apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs implement ONE
#     predicate spec, bound by the shared corpus ./filing-shape-corpus.json that
#     both suites run. A spelling change goes in the corpus first.
#   * guardrails.sh unions this lexer's findings with main's older detectors
#     (the CLASS 1 grep and _api_pl) — the "floor". Each record says whether the
#     floor could have seen it (`vis=1`: not inside quotes, a heredoc body or a
#     runner string), and only visible records offset the floor's count. The
#     floor may be removed only after `filing-shape.test.sh --differential` has
#     run clean on three consecutive filing-gate changes (ADR-256).
#
# GRAMMAR (what is modelled; everything else is an ordinary word character):
#   script    := command ( SEP command )*
#   blanks    := space and tab ONLY. Bash reads \r, \f and \v as word characters,
#                so this lexer must too: splitting on them would let
#                `--body=x\r-mM` forge a milestone bash never passes.
#   SEP       := newline ; & | && || |& ;; ;& ;;& ( )      — an unbalanced ( ) is a
#                separator, never an error.
#   case      := `case W in PAT) … ;; esac` — a pattern's `)` closes the pattern,
#                never an enclosing $(…).
#   (( … ))   := an arithmetic command at command position (also `for ((…))`):
#                its `<<` is a shift, never a heredoc. A `((` that does not close
#                with `))` is re-read as two subshells, as bash does.
#   redirect  := [fd] ( <<< << <<- &>> &> >> >| >& <& <> > < ) word — dropped
#                from argv; substitutions inside the target are still lexed.
#   word      := ( plain | \x | '…' | "…" | $'…' | $"…" | $(…) | $((…)) | ${…}
#                | ${ cmd; } | ${| cmd; } | `…` | <(…) | >(…) | $NAME )+
#   $(…) <(…) >(…) ${ …; }  lexed IN PLACE from the same cursor, each with its OWN
#                heredoc queue (bash drains an outer heredoc only at a newline of
#                the outer command, never at one inside a substitution).
#   `…`       extracted (backslash-unescaped; `\"` too inside "…") and lexed as
#             its own string.
#   $'…'      decoded (\n \t \xHH \NNN \uHHHH \cX …), so an escape cannot hide a
#             separator or a word from the lexer.
#   ${…} $((…)) their TEXT is never a script; substitutions inside them are.
#   #         starts a comment only at the start of a word.
#   heredoc   body starts at the next unquoted newline; a quoted delimiter
#             ('EOF' "EOF" \EOF E"OF") makes it data, an unquoted one is scanned
#             for $( ` ${ like a double-quoted string.
#   runners   bash|sh|zsh|dash|ksh with an option cluster holding `c` (each `o`/`O`
#             in any cluster consumes one value), and `eval` — their string is
#             lexed again. Everything else that runs a string is a Non-Goal.
#   filings   every argv index whose basename is `gh` and whose next word is
#             `issue`, `api` or a flag starts a candidate; when any find action
#             (-exec -execdir -ok -okdir) precedes it, it is cut at `;` or `+`.
#
# BODY CORPUS. A filing's `body=` field is what bash will actually pass: the
# body word's LITERAL text, plus the heredoc bodies drained inside that word
# (`--body "$(cat <<'EOF' … EOF)"`), plus the literal values assigned to each
# variable the word references (`B=…` / `B=$(cat <<'EOF' …)` / `read … B <<EOF`).
# Command-substitution TEXT is never corpus: `$(true Mandated-By: hr-x)` expands
# to nothing.
#
# MODES:
#   perl filing-shape.pl            stdin = raw command. stdout = NUL-framed
#       records `F\0<shape>\0<ctx>\0<nfields>\0<k=v>\0…` then `OK\0`, exit 0.
#       Parse BY COUNT, never by searching for `F` or `OK`.
#       exit 2: agent-fixable syntax (unbalanced quote, unterminated substitution,
#               missing heredoc delimiter word, NUL byte). exit 3: a bound tripped
#               (`depth` > 16; `budget` — 8*input+64KiB, ONE global counter every
#               frame and the output charge; `alarm` 2 s; `records` > 32 filings)
#               or the lexer itself died (`crash`). Either way stdout is exactly
#               `E\0<cause>\0` and stderr carries `bound=<cause>`.
#   perl filing-shape.pl --classify tok…   print create|api|none (corpus entry).
#   perl filing-shape.pl --trace           argv per simple command with its
#       wrapper path, plus each filing's fields — use it to debug a false deny.
#       Feed it the command from a FILE (`… --trace < cmd.txt`): pasting a command
#       into a double-quoted argument would run its substitutions.
#   perl filing-shape.pl --tables          the gh version and value-flag tables.
#
# FLAG TABLES are gh 2.101.0 (2026-09-15), read from `gh help issue create` and
# `gh help api`. Refresh: run `bash .claude/hooks/lib/filing-shape.test.sh` with
# that gh installed; its staleness row diffs these tables against gh's help.
use strict;
BEGIN { $^W = 1 }

# ---- data ---------------------------------------------------------------------
my $GH_VERSION = '2.101.0';
# Value-taking flags. A token that is the VALUE of one of these is never read as
# a flag, so `--title -mx` does not grant a milestone. `-R/--repo` is the
# `gh issue` group flag (gh api has no such flag).
my @CREATE_VAL = qw(-a --assignee --attach --blocked-by --blocking -b --body
  -F --body-file -l --label -m --milestone --parent -p --project --recover
  -T --template -t --title --type -R --repo);
my @API_VAL = qw(--cache -F --field -H --header --hostname --input -q --jq
  -X --method -p --preview -f --raw-field -t --template);
my %CREATE_VAL = map { $_ => 1 } @CREATE_VAL;
my %API_VAL    = map { $_ => 1 } @API_VAL;
# The three marker pairs below delimit the lexer code shared byte for byte with
# plugins/soleur/hooks/lib/shell-argv.pl (the plugin's destructive-command guard lexer). Edit a
# span in BOTH files; plugins/soleur/test/shell-argv-parity.test.sh fails on any divergence.
# Span 1 also holds %FIND_ACT and $MAX_RECORDS, which only this file uses: they sit between
# lexer constants and moving them would not be a comment-only change.
# BEGIN SHARED-LEXER
my %RUNNER     = map { $_ => 1 } qw(bash sh zsh dash ksh);
my %FIND_ACT   = map { $_ => 1 } qw(-exec -execdir -ok -okdir);
my %RESERVED   = map { $_ => 1 } qw(! { then do else elif if while until time);

my $MAX_DEPTH   = 16;
my $MAX_RECORDS = 32;
my $ALARM_S     = 2;
# END SHARED-LEXER

# The predicate (same spec as filingShape(); `\z` where JS uses `$`).
my $ISSUES_COLLECTION_RE = qr~(?<![A-Za-z0-9_])(?:repos/[^/?#\s]+(?:/[^/?#\s]+)?|repositories/[0-9]+)/issues(?:/?(?:[?#].*)?|[\$})][^/]*)\z~;
my $BARE_EXPANSION_RE = qr~^\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[^{}]*\})\z~;
my $PARTIAL_TAIL_RE = qr~(?:^|/)issues/?(?:[?#].*)?\z~;
my $V = qr~(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]*\})?~;

# ---- state --------------------------------------------------------------------
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

# ---- predicate ----------------------------------------------------------------
sub post_signal {
  my ($t, $n) = @_;
  $n = '' unless defined $n;
  return 1 if ($t =~ /^${V}(?:-i*X|--method)\z/) && ($n =~ /^post\z/i || $n =~ /^[\$`]/);
  return 1 if $t =~ /^${V}(?:-i*X=?|--method=)(?:[Pp][Oo][Ss][Tt]\z|[\$`])/;
  return 1 if $t =~ /^${V}--input(?:=|\z)/;
  return 1 if ($t =~ /^${V}(?:-i*[fF]|--(?:raw-)?field)\z/) && $n =~ /^(?:title=|[\$`])/;
  return 1 if $t =~ /^${V}(?:-i*[fF]=?|--field=|--raw-field=)?title=/;
  return 1 if $t =~ /^${V}(?:-i*[fF]=?|--field=|--raw-field=)[\$`]/;
  return 0;
}

# A repos/…|repositories/… path with a `.` / `..` segment (matrix params `;…`
# stripped) or a `%2e` segment: GitHub normalizes it, so `labels/../issues` IS
# the collection. LINEAR by construction: one boundary search, then one split of
# the tail after the FIRST occurrence (every later occurrence lies inside it).
sub dot_segment {
  my $t = shift;
  for my $piece (split /[?#\s]/, $t) {
    next unless $piece =~ m~(?<![A-Za-z0-9_])(?:repos|repositories)/~g;
    for my $seg (split m~/~, substr($piece, pos($piece))) {
      (my $bare = $seg) =~ s/;.*//s;
      return 1 if $bare eq '.' || $bare eq '..' || $seg =~ /%2e/i;
    }
  }
  return 0;
}

# The first positional argument after `api` — the endpoint gh routes — with the
# values of gh api's value-taking flags skipped.
sub api_endpoint_arg {
  my @t = @_;
  my $i = 0;
  $i++ while $i < @t && $t[$i] ne 'api';
  for (my $j = $i + 1; $j < @t; $j++) {
    my $a = $t[$j];
    if ($a eq '--') { return $t[$j + 1] }
    if ($a =~ /^--[^=]+=/) { next }
    if ($a =~ /^--./) { $j++ if $API_VAL{$a}; next }
    if ($a =~ /^-([A-Za-z]+.*)\z/s) {
      my $cl = $1;
      for my $k (0 .. length($cl) - 1) {
        my $ch = substr($cl, $k, 1);
        next unless $API_VAL{"-$ch"};
        $j++ if $k == length($cl) - 1;   # value is the next word
        last;
      }
      next;
    }
    return $a;
  }
  return undef;
}

sub filing_shape {
  my @t = @_;
  return 'none' unless @t && $t[0] eq 'gh';
  my @pos;
  for (my $i = 1; $i < @t; $i++) {
    if ($t[$i] eq '-R' || $t[$i] eq '--repo') { $i++; next }
    push @pos, $t[$i] unless $t[$i] =~ /^-/;
  }
  return 'create' if @pos >= 2 && $pos[0] eq 'issue' && ($pos[1] eq 'create' || $pos[1] eq 'new');
  return 'none' unless @pos && $pos[0] eq 'api';
  my $ep = api_endpoint_arg(@t);
  my $endpoint = (grep { $_ =~ $ISSUES_COLLECTION_RE || dot_segment($_) } @t) ? 1 : 0;
  # An unexpanded value leans toward gating — but only in the ENDPOINT position:
  # a `--jq "$Q"` or `--input "$F"` on a pulls POST is not an issues endpoint.
  $endpoint ||= 1 if defined $ep
    && ($ep =~ $BARE_EXPANSION_RE || ($ep =~ /[\$`]/ && $ep =~ $PARTIAL_TAIL_RE));
  return 'none' unless $endpoint;
  for my $i (0 .. $#t) { return 'api' if post_signal($t[$i], $t[$i + 1]) }
  return 'none';
}

# ---- per-filing fields (Guard 2: a filing's exits come from its own argv) -----
# Returns [name, value-text, word-index, literal-prefix-length] per option: the
# word at word-index carries the value, after `prefix` literal characters.
sub parse_opts {
  my ($shape, $c) = @_;
  my $val = $shape eq 'create' ? \%CREATE_VAL : \%API_VAL;
  my (@opts, @pos);
  my $j = 1;
  while ($j < @$c) {
    my $a = $c->[$j];
    if ($a eq '--') { push @pos, @$c[$j + 1 .. $#$c]; last }
    if ($a =~ /^(--[^=]+)=(.*)\z/s) { push @opts, [$1, $2, $j, length($1) + 1]; $j++; next }
    if ($a =~ /^--./) {
      if ($val->{$a}) { push @opts, [$a, $c->[$j + 1], $j + 1, 0]; $j += 2 }
      else { push @opts, [$a, undef, undef, 0]; $j++ }
      next;
    }
    if ($a =~ /^-([A-Za-z].*)\z/s) {
      my $cl = $1;
      my $k = 0;
      my $took_next = 0;
      while ($k < length $cl) {
        my $ch = substr($cl, $k, 1);
        if ($val->{"-$ch"}) {
          my $v = substr($cl, $k + 1);
          my $pre = $k + 2;
          if ($v =~ s/^=//) { $pre++ }
          if ($v eq '') { push @opts, ["-$ch", $c->[$j + 1], $j + 1, 0]; $took_next = 1 }
          else { push @opts, ["-$ch", $v, $j, $pre] }
          last;
        }
        push @opts, ["-$ch", undef, undef, 0];
        $k++;
      }
      $j += 1 + $took_next;
      next;
    }
    push @pos, $a;
    $j++;
  }
  return (\@opts, \@pos);
}

# [HOST/]OWNER/REPO in every spelling gh resolves: a scheme URL, an scp-style
# `git@host:owner/repo`, a bare host prefix. The owner is lowercased. A value
# holding `$` or a backtick is returned verbatim (never external, guardrails.sh).
sub normalize_repo {
  my $r = shift;
  return $r if $r =~ /[\$`]/;
  $r =~ s{^[A-Za-z][A-Za-z0-9+.-]*://}{};
  $r =~ s{^[^@/]*@}{};
  $r =~ s{^[^/:]+:}{};
  $r =~ s{\.git\z}{};
  my @seg = split m{/}, $r, -1;
  shift @seg if @seg >= 3 && $seg[0] =~ /\./;
  $seg[0] = lc $seg[0] if @seg;
  return join '/', @seg;
}

# The body corpus of one value (see the header): literal text after `$pre`
# literal characters, the word's heredoc bodies, and each referenced variable's
# literal values.
sub value_corpus {
  my ($w, $pre, $strip) = @_;
  my $lit = substr($w->{lit}, $pre);
  $lit =~ s/^\Q$strip\E// if defined $strip;
  my @parts = ($lit, @{ $w->{hd} });
  my $t = substr($w->{t}, $pre);
  my %seen;
  while ($t =~ /\$\{?([A-Za-z_][A-Za-z0-9_]*)/g) {
    next if $seen{$1}++;
    push @parts, @{ $VARS{$1} } if $VARS{$1};
  }
  return join "\n", grep { length } @parts;
}

sub fields_of {
  my ($shape, $cw) = @_;
  my @c = map { $_->{t} } @$cw;
  my ($opts, $pos) = parse_opts($shape, \@c);
  my (@f, $repo, $milestone, $bodyfile, $body, $input);
  my $head;
  if ($shape eq 'create') { $head = 'gh issue ' . ($pos->[1] // 'create') }
  else {
    my $ep = api_endpoint_arg(@c);
    $ep = '' unless defined $ep;
    $ep =~ s/[?#].*//s;
    $head = substr('gh api ' . $ep, 0, 64);
  }
  my @labels;
  for my $o (@$opts) {
    my ($n, $v, $wi, $pre) = @$o;
    if ($n eq '-R' || $n eq '--repo') { $repo = $v if defined $v; next }
    if ($shape eq 'create') {
      if ($n eq '-m' || $n eq '--milestone') { $milestone = 1 if defined $v && length $v }
      elsif ($n eq '-l' || $n eq '--label') { push @labels, $v if defined $v }
      elsif ($n eq '-F' || $n eq '--body-file') { $bodyfile = $v if defined $v }
      elsif (($n eq '-b' || $n eq '--body') && defined $v) { $body = value_corpus($cw->[$wi], $pre) }
    } else {
      next unless defined $v;
      if ($n eq '--input') { $input = 1 }
      elsif ($n =~ /^(?:-f|-F|--field|--raw-field)\z/) {
        # -F/--field read `@path` as a file; -f/--raw-field send it literally.
        my $typed = ($n eq '-F' || $n eq '--field');
        if ($v =~ /^labels\[\]=(.*)\z/s) { push @labels, $1 }
        elsif ($typed && $v =~ /^body=@(.*)\z/s) { $bodyfile = $1; $body = undef }
        elsif ($v =~ /^body=/) { $body = value_corpus($cw->[$wi], $pre, 'body='); $bodyfile = undef }
      }
    }
  }
  push @f, "head=$head";
  push @f, "repo=" . normalize_repo($repo) if defined $repo;
  push @f, "milestone=1" if $milestone;
  push @f, "label=$_" for @labels;
  push @f, "bodyfile=$bodyfile" if defined $bodyfile;
  push @f, "body=$body" if defined $body;
  push @f, "input=1" if $input;
  return \@f;
}

# ---- lexer --------------------------------------------------------------------
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

sub process_command {
  my ($words, $ctx, $cmd) = @_;
  my @t = map { $_->{t} } @$words;
  print STDERR join('>', @PATH), ': ', join(' ', map { "[$_]" } @t), "\n" if $TRACE;
  my $i = 0;
  $i++ while $i < @t && !$words->[$i]{q} && $RESERVED{ $t[$i] };
  # `read … NAME <<EOF` binds the heredoc (drained after this flush) to NAME.
  if ($i < @t && $t[$i] =~ /^(?:read|mapfile|readarray)\z/ && $t[-1] =~ /^[A-Za-z_][A-Za-z0-9_]*\z/) {
    $cmd->{name} = $t[-1];
  }
  my $assign = sub {
    my $w = shift;
    return unless $w->{t} =~ /^([A-Za-z_][A-Za-z0-9_]*)=/;
    my $name = $1;
    my $lit = $w->{lit} =~ /^\Q$name\E=/ ? substr($w->{lit}, length($name) + 1) : '';
    push @{ $VARS{$name} }, grep { length } ($lit, @{ $w->{hd} });
  };
  my $a = $i;
  while ($a < @t && $t[$a] =~ /^[A-Za-z_][A-Za-z0-9_]*=/) { $assign->($words->[$a]); $a++ }
  if ($a < @t && $t[$a] =~ /^(?:export|local|declare|readonly|typeset)\z/) {
    $assign->($words->[$_]) for $a + 1 .. $#t;
  }
  for my $k (0 .. $#t) {
    next unless basename_of($t[$k]) eq 'gh';
    next unless $k < $#t && $t[$k + 1] =~ /^(?:issue|api)\z|^-/;
    my @cw = (new_word(), @$words[$k + 1 .. $#t]);
    $cw[0]{t} = 'gh';
    if (grep { $FIND_ACT{$_} } @t[0 .. $k - 1]) {
      for my $e (1 .. $#cw) { if ($cw[$e]{t} eq ';' || $cw[$e]{t} eq '+') { splice @cw, $e; last } }
    }
    my $shape = filing_shape(map { $_->{t} } @cw);
    next if $shape eq 'none';
    my $f = fields_of($shape, \@cw);
    push @$f, 'vis=1' unless $INVIS;
    push @RECORDS, [$shape, $ctx, $f];
    fail3('records') if @RECORDS > $MAX_RECORDS;
    print STDERR "  FILING $shape ctx=$ctx ", join(' | ', @$f), "\n" if $TRACE;
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

# ---- entry --------------------------------------------------------------------
if (@ARGV && $ARGV[0] eq '--classify') { shift @ARGV; print filing_shape(@ARGV), "\n"; exit 0 }
if (@ARGV && $ARGV[0] eq '--tables') {
  print "gh $GH_VERSION\ncreate-val @CREATE_VAL\napi-val @API_VAL\n";
  exit 0;
}
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
    my ($shape, $ctx, $f) = @$r;
    my $rec = join("\0", 'F', $shape, $ctx, scalar(@$f), @$f) . "\0";
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
