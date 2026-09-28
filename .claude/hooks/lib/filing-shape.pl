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
#     (the CLASS 1 grep and _api_pl) — the "floor". The floor may be removed
#     only after `filing-shape.test.sh --differential` has run clean on three
#     consecutive filing-gate changes (ADR-256 records the criterion).
#
# GRAMMAR (what is modelled; everything else is an ordinary word character):
#   script    := command ( SEP command )*
#   SEP       := newline ; & | && || |& ;; ;& ;;& ( )      — unbalanced ( ) are
#                separators, never errors, so `case` and `[[ =~ (a|b) ]]` lex.
#   redirect  := [fd] ( <<< << <<- &>> &> >> >| >& <& <> > < ) word — dropped
#                from argv; substitutions inside the target are still lexed.
#   word      := ( plain | \x | '…' | "…" | $'…' | $"…" | $(…) | $((…)) | ${…}
#                | `…` | <(…) | >(…) | $NAME )+
#   $(…) <(…) >(…)  lexed IN PLACE from the same cursor (so a heredoc body inside
#                   `$(cat <<'EOF' … EOF)` may hold `)`, `it's`, backticks).
#   `…`       extracted (backslash-unescaped) then lexed as its own string.
#   ${…} $((…)) their TEXT is never a script; substitutions inside them are.
#   #         starts a comment only at the start of a word.
#   heredoc   body starts at the next unquoted newline; a quoted delimiter
#             ('EOF' "EOF" \EOF E"OF") makes it data, an unquoted one is scanned
#             for $( ` ${ like a double-quoted string. Bodies and literal
#             NAME=value assignment values form the "variable corpus".
#   runners   bash|sh|zsh|dash|ksh with an option cluster holding `c` (options and
#             their values before or after it), and `eval` — their string is
#             lexed again. Everything else that runs a string is a Non-Goal.
#   filings   every argv index whose basename is `gh` starts a candidate; after
#             find -exec/-execdir/-ok/-okdir the candidate is cut at `;` or `+`.
#
# MODES:
#   perl filing-shape.pl            stdin = raw command. stdout = NUL-framed
#       records `F\0<shape>\0<ctx>\0<nfields>\0<k=v>\0…` then `OK\0`, exit 0.
#       Parse BY COUNT, never by searching for `F` or `OK`.
#       exit 2: agent-fixable syntax (unbalanced quote, unterminated substitution,
#               missing heredoc delimiter word, NUL byte). exit 3: a bound tripped
#               (depth > 16, character budget 8*input+64KiB charged on ONE global
#               counter, alarm 2 s). Either way stdout is exactly `E\0<cause>\0`
#               and stderr carries `bound=<cause>`.
#   perl filing-shape.pl --classify tok…   print create|api|none (corpus entry).
#   perl filing-shape.pl --trace           argv per simple command with its
#       wrapper path, plus each filing's fields — use it to debug a false deny.
#   perl filing-shape.pl --tables          the gh flag tables (staleness row).
#
# FLAG TABLES are gh 2.101.0 (2026-09-15), read from `gh help issue create` and
# `gh help api`. Refresh: run `bash .claude/hooks/lib/filing-shape.test.sh`; its
# staleness row diffs these tables against the installed gh and names the drift.
use strict;
BEGIN { $^W = 1 }

# ---- data ---------------------------------------------------------------------
my $GH_VERSION = '2.101.0';
# Value-taking flags. A token that is the VALUE of one of these is never read as
# a flag, so `--title -mx` does not grant a milestone.
my @CREATE_VAL = qw(-a --assignee --attach --blocked-by --blocking -b --body
  -F --body-file -l --label -m --milestone --parent -p --project --recover
  -T --template -t --title --type -R --repo);
my @CREATE_BOOL = qw(-e --editor -w --web);
my @API_VAL = qw(--cache -F --field -H --header --hostname --input -q --jq
  -X --method -p --preview -f --raw-field -t --template -R --repo);
my @API_BOOL = qw(--allow-escape-sequences -i --include --paginate --silent
  --slurp --verbose);
my %CREATE_VAL = map { $_ => 1 } @CREATE_VAL;
my %API_VAL    = map { $_ => 1 } @API_VAL;
my %RUNNER     = map { $_ => 1 } qw(bash sh zsh dash ksh);
my %FIND_ACT   = map { $_ => 1 } qw(-exec -execdir -ok -okdir);

my $MAX_DEPTH = 16;
my $ALARM_S   = 2;

# The predicate (same spec as filingShape(); `\z` where JS uses `$`).
my $ISSUES_COLLECTION_RE = qr~(?<![A-Za-z0-9_])(?:repos/[^/?#\s]+(?:/[^/?#\s]+)?|repositories/[0-9]+)/issues(?:/?(?:[?#].*)?|[\$})][^/]*)\z~s;
my $DOT_SEGMENT_RE = qr~(?<![A-Za-z0-9_])(?:repos|repositories)/(?:[^?#\s]*/)?(?:\.\.?|[^/?#\s]*%2[eE][^/?#\s]*)(?:[/?#]|\z)~;
my $BARE_EXPANSION_RE = qr~^\$(?:[A-Za-z_][A-Za-z0-9_]*|\{[^{}]*\})\z~;
my $PARTIAL_TAIL_RE = qr~(?:^|/)issues/?(?:[?#].*)?\z~s;
my $V = qr~(?:\$[A-Za-z_][A-Za-z0-9_]*|\$\{[^}]*\})?~;

# ---- state --------------------------------------------------------------------
my ($BUDGET, $USED, $DEPTH) = (0, 0, 0);
my (@RECORDS, @VARCORPUS, @PATH, %SEEN_SUBST, %SEEN_STR);
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

sub is_issues_endpoint {
  my $t = shift;
  return 1 if $t =~ $ISSUES_COLLECTION_RE || $t =~ $BARE_EXPANSION_RE;
  return 1 if $t =~ /[\$`]/ && $t =~ $PARTIAL_TAIL_RE;
  return $t =~ $DOT_SEGMENT_RE ? 1 : 0;
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
  return 'none' unless grep { is_issues_endpoint($_) } @t;
  for my $i (0 .. $#t) { return 'api' if post_signal($t[$i], $t[$i + 1]) }
  return 'none';
}

# ---- per-filing fields (Guard 2: a filing's exits come from its own argv) -----
sub parse_opts {
  my ($shape, $c, $cx) = @_;
  my $val = $shape eq 'create' ? \%CREATE_VAL : \%API_VAL;
  my (@opts, @pos);
  my $j = 1;
  while ($j < @$c) {
    my $a = $c->[$j];
    if ($a eq '--') { push @pos, @$c[$j + 1 .. $#$c]; last }
    if ($a =~ /^(--[^=]+)=(.*)\z/s) { push @opts, [$1, $2, $cx->[$j]]; $j++; next }
    if ($a =~ /^--./) {
      if ($val->{$a}) { push @opts, [$a, $c->[$j + 1], $cx->[$j + 1]]; $j += 2 }
      else { push @opts, [$a, undef, 0]; $j++ }
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
          $v =~ s/^=//;
          if ($v eq '') { push @opts, ["-$ch", $c->[$j + 1], $cx->[$j + 1]]; $took_next = 1 }
          else { push @opts, ["-$ch", $v, $cx->[$j]] }
          last;
        }
        push @opts, ["-$ch", undef, 0];
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

sub normalize_repo {
  my $r = shift;
  return $r if $r =~ /[\$`]/;
  $r =~ s{^[A-Za-z][A-Za-z0-9+.-]*://}{};
  my @seg = split m{/}, $r, -1;
  shift @seg if @seg >= 3 && $seg[0] =~ /\./;   # [HOST/]OWNER/REPO
  $seg[0] = lc $seg[0] if @seg;
  return join '/', @seg;
}

sub fields_of {
  my ($shape, $c, $cx) = @_;
  my ($opts, $pos) = parse_opts($shape, $c, $cx);
  my (@f, $repo, $milestone, $bodyfile, $body, $bodyx, $input);
  my $head;
  if ($shape eq 'create') { $head = 'gh issue ' . ($pos->[1] // 'create') }
  else {
    my $ep = $pos->[1];
    $ep = (grep { is_issues_endpoint($_) } @$c)[0] unless defined $ep && is_issues_endpoint($ep);
    $ep = '' unless defined $ep;
    $ep =~ s/[?#].*//s;
    $head = substr('gh api ' . $ep, 0, 64);
  }
  my @labels;
  for my $o (@$opts) {
    my ($n, $v, $x) = @$o;
    if ($n eq '-R' || $n eq '--repo') { $repo = $v if defined $v; next }
    if ($shape eq 'create') {
      if ($n eq '-m' || $n eq '--milestone') { $milestone = 1 }
      elsif ($n eq '-l' || $n eq '--label') { push @labels, $v if defined $v }
      elsif ($n eq '-F' || $n eq '--body-file') { $bodyfile = $v if defined $v }
      elsif ($n eq '-b' || $n eq '--body') { if (defined $v) { $body = $v; $bodyx = $x } }
    } else {
      if ($n eq '--input') { $input = 1 }
      elsif ($n =~ /^(?:-f|-F|--field|--raw-field)\z/ && defined $v) {
        if ($v =~ /^labels\[\]=(.*)\z/s) { push @labels, $1 }
        elsif ($v =~ /^body=@(.*)\z/s) { $bodyfile = $1 }
        elsif ($v =~ /^body=(.*)\z/s) { $body = $1; $bodyx = $x }
      }
    }
  }
  push @f, "head=$head";
  push @f, "repo=" . normalize_repo($repo) if defined $repo;
  push @f, "milestone=1" if $milestone;
  push @f, "label=$_" for @labels;
  push @f, "bodyfile=$bodyfile" if defined $bodyfile;
  if (defined $body) {
    push @f, "body=$body";
    push @f, "bodyvar=1" if $bodyx;
  }
  push @f, "input=1" if $input;
  return \@f;
}

# ---- lexer --------------------------------------------------------------------
sub lex_string {
  my ($text, $ctx) = @_;
  return if $SEEN_STR{$text}++;          # memoized: a string is lexed once
  charge(length $text);
  my $st = new_state($text);
  push @PATH, $ctx;
  parse_list($st, $ctx, 'eof');
  pop @PATH;
}

sub parse_list {
  my ($st, $ctx, $term) = @_;
  enter();
  my $sr = $st->{s};
  my @words;
  my $parens = 0;
  my $flush = sub { if (@words) { process_command([@words], $ctx); @words = () } };
  while (1) {
    if ($$sr =~ /\G[ \t\r]+/gc) { next }
    if ($$sr =~ /\G\\\n/gc) { next }
    if (at_end($sr)) {
      $flush->();
      fail2('unterminated $( or <(') if $term eq ')';
      last;
    }
    my $p0 = pos($$sr);
    if ($$sr =~ /\G\n/gc) { charge(1); $flush->(); drain_heredocs($st); next }
    if ($$sr =~ /\G#[^\n]*/gc) { charge(pos($$sr) - $p0); next }
    if (peek($sr, 2) =~ /^[<>]\(/) { push @words, parse_word($st, $ctx); next }
    if ($$sr =~ /\G(?:\d+|\{[A-Za-z_][A-Za-z0-9_]*\})?(<<<|<<-|<<|&>>|&>|>>|>\||>&|<&|<>|>|<)/gc) {
      my $op = $1;
      charge(pos($$sr) - $p0);
      $$sr =~ /\G[ \t]+/gc;
      if ($op eq '<<' || $op eq '<<-') {
        fail2('missing heredoc delimiter') if at_end($sr) || peek($sr) =~ /[\n;&|()<>]/;
        my $w = parse_word($st, $ctx);
        push @{ $st->{hq} }, { delim => $w->{t}, quoted => $w->{q}, strip => $op eq '<<-' };
      } elsif (!at_end($sr) && peek($sr) !~ /[\n;&|()<>]/) {
        parse_word($st, $ctx);            # target dropped; its substitutions lexed
      }
      next;
    }
    if ($$sr =~ /\G(?:;;&|;;|;&|;|&&|\|\||\|&|\||&)/gc) { charge(pos($$sr) - $p0); $flush->(); next }
    if ($$sr =~ /\G\(/gc) { charge(1); $parens++; $flush->(); next }
    if ($$sr =~ /\G\)/gc) {
      charge(1);
      $flush->();
      if ($parens > 0) { $parens--; next }
      if ($term eq ')') { leave(); return }
      next;                               # a stray ) is a separator
    }
    push @words, parse_word($st, $ctx);
  }
  leave();
}

# One shell word. Returns { t => dequoted text (expansions kept as raw source),
# x => contains an expansion, q => any quoting seen }.
sub parse_word {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $w = { t => '', x => 0, q => 0 };
  while (1) {
    my $p0 = pos($$sr);
    if ($$sr =~ /\G([^\s;&|()<>\\'"\$`]+)/gc) { $w->{t} .= $1; charge(length $1); next }
    last if at_end($sr);
    my $c = peek($sr);
    if ($c eq '\\') {
      if ($$sr =~ /\G\\\n/gc) { charge(2); next }
      if ($$sr =~ /\G\\(.)/gcs) { $w->{t} .= $1; $w->{q} = 1; charge(2); next }
      $$sr =~ /\G\\/gc; $w->{t} .= '\\'; next;
    }
    if ($c eq "'") {
      $$sr =~ /\G'([^']*)'/gc or fail2("unbalanced '");
      $w->{t} .= $1; $w->{q} = 1; charge(pos($$sr) - $p0); next;
    }
    if ($c eq '"') { $$sr =~ /\G"/gc; $w->{q} = 1; parse_dq($st, $ctx, $w); next }
    if ($c eq '$') {
      if ($$sr =~ /\G\$'((?:[^'\\]|\\.)*)'/gcs) {
        my $v = $1; $v =~ s/\\(['\\])/$1/g;
        $w->{t} .= $v; $w->{q} = 1; charge(pos($$sr) - $p0); next;
      }
      fail2("unbalanced \$'") if peek($sr, 2) eq "\$'";
      if (peek($sr, 2) eq '$"') { $$sr =~ /\G\$"/gc; $w->{q} = 1; parse_dq($st, $ctx, $w); next }
      dollar($st, $ctx, $w, 0); next;
    }
    if ($c eq '`') { $w->{t} .= parse_backtick($st, $ctx); $w->{x} = 1; next }
    if (peek($sr, 2) =~ /^[<>]\(/) { $w->{t} .= parse_subst($st, $ctx, 2); $w->{x} = 1; next }
    last;                                  # blank, separator, ( ) < >
  }
  return $w;
}

# `$…` in a word, a double-quoted string or a heredoc body.
sub dollar {
  my ($st, $ctx, $w, $in_dq) = @_;
  my $sr = $st->{s};
  my $p0 = pos($$sr);
  if (peek($sr, 3) eq '$((') { $w->{t} .= parse_arith($st, $ctx); $w->{x} = 1; return }
  if (peek($sr, 2) eq '$(')  { $w->{t} .= parse_subst($st, $ctx, 2); $w->{x} = 1; return }
  if (peek($sr, 2) eq '${')  { $w->{t} .= parse_brace($st, $ctx, $in_dq); $w->{x} = 1; return }
  if ($$sr =~ /\G(\$(?:[A-Za-z_][A-Za-z0-9_]*|[0-9?\$@*#!-]))/gc) {
    $w->{t} .= $1; $w->{x} = 1; charge(length $1); return;
  }
  $$sr =~ /\G\$/gc; $w->{t} .= '$'; charge(1);
}

# After the opening `"`; consumes through the closing `"`.
sub parse_dq {
  my ($st, $ctx, $w) = @_;
  my $sr = $st->{s};
  while (1) {
    if ($$sr =~ /\G([^"\\\$`]+)/gc) { $w->{t} .= $1; charge(length $1); next }
    fail2('unbalanced "') if at_end($sr);
    my $c = peek($sr);
    if ($c eq '"') { $$sr =~ /\G"/gc; charge(1); return }
    if ($c eq '\\') {
      if ($$sr =~ /\G\\\n/gc) { charge(2); next }
      if ($$sr =~ /\G\\([\$`"\\])/gc) { $w->{t} .= $1; charge(2); next }
      $$sr =~ /\G\\/gc; $w->{t} .= '\\'; charge(1); next;
    }
    if ($c eq '`') { $w->{t} .= parse_backtick($st, $ctx); $w->{x} = 1; next }
    dollar($st, $ctx, $w, 1);
  }
}

# `$(…)`, `<(…)`, `>(…)` — lexed in place. Returns the raw source.
sub parse_subst {
  my ($st, $ctx, $oplen) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  pos($$sr) = $start + $oplen;
  charge($oplen);
  my $n0 = @RECORDS;
  push @PATH, 'subst';
  parse_list($st, 'subst', ')');
  pop @PATH;
  my $raw = substr($$sr, $start, pos($$sr) - $start);
  my $inner = substr($raw, $oplen, -1);
  # Seen before (the same text reached again through a runner string): its
  # filings were already recorded once.
  splice @RECORDS, $n0 if $SEEN_SUBST{$inner}++;
  return $raw;
}

sub parse_backtick {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $p0 = pos($$sr);
  $$sr =~ /\G`((?:[^`\\]|\\.)*)`/gcs or fail2('unbalanced `');
  my $body = $1;
  charge(pos($$sr) - $p0);
  (my $inner = $body) =~ s/\\([\$`\\])/$1/g;
  unless ($SEEN_SUBST{$inner}++) {
    enter();
    push @PATH, 'backtick';
    my $st2 = new_state($inner);
    parse_list($st2, 'backtick', 'eof');
    pop @PATH;
    leave();
  }
  return substr($$sr, $p0, pos($$sr) - $p0);
}

# `${…}`: its text is never a script; substitutions inside it are lexed.
sub parse_brace {
  my ($st, $ctx, $in_dq) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  $$sr =~ /\G\$\{/gc; charge(2);
  enter();
  my $scratch = { t => '', x => 0, q => 0 };
  while (1) {
    if ($$sr =~ /\G([^{}\$`'"\\]+)/gc) { charge(length $1); next }
    fail2('unterminated ${') if at_end($sr);
    my $c = peek($sr);
    if ($c eq '}') { $$sr =~ /\G\}/gc; charge(1); last }
    if ($c eq '{') { $$sr =~ /\G\{/gc; charge(1); next }
    if ($c eq '\\') { $$sr =~ /\G\\.?/gcs; charge(2); next }
    if ($c eq "'") {
      if ($in_dq) { $$sr =~ /\G'/gc; charge(1); next }
      my $p0 = pos($$sr);
      $$sr =~ /\G'[^']*'/gc or fail2("unbalanced ' in \${");
      charge(pos($$sr) - $p0); next;
    }
    if ($c eq '"') { $$sr =~ /\G"/gc; parse_dq($st, $ctx, $scratch); next }
    if ($c eq '`') { parse_backtick($st, $ctx); next }
    dollar($st, $ctx, $scratch, $in_dq);
  }
  leave();
  return substr($$sr, $start, pos($$sr) - $start);
}

# `$((…))`: arithmetic text is not a script; substitutions inside it are.
sub parse_arith {
  my ($st, $ctx) = @_;
  my $sr = $st->{s};
  my $start = pos($$sr);
  $$sr =~ /\G\$\(\(/gc; charge(3);
  enter();
  my $d = 0;
  my $scratch = { t => '', x => 0, q => 0 };
  while (1) {
    if ($$sr =~ /\G([^()\$`'"\\]+)/gc) { charge(length $1); next }
    fail2('unterminated $((') if at_end($sr);
    my $c = peek($sr);
    if ($c eq '(') { $$sr =~ /\G\(/gc; $d++; charge(1); next }
    if ($c eq ')') {
      $$sr =~ /\G\)/gc; charge(1);
      if ($d > 0) { $d--; next }
      $$sr =~ /\G\)/gc;
      last;
    }
    if ($c eq '\\') { $$sr =~ /\G\\.?/gcs; charge(2); next }
    if ($c eq "'") { my $p0 = pos($$sr); $$sr =~ /\G'[^']*'/gc or fail2("unbalanced ' in \$(("); charge(pos($$sr) - $p0); next }
    if ($c eq '"') { $$sr =~ /\G"/gc; parse_dq($st, $ctx, $scratch); next }
    if ($c eq '`') { parse_backtick($st, $ctx); next }
    dollar($st, $ctx, $scratch, 0);
  }
  leave();
  return substr($$sr, $start, pos($$sr) - $start);
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
      (my $cmp = $line) =~ s/^\t+// if $h->{strip};
      $cmp = $line unless $h->{strip};
      last if $cmp eq $h->{delim};
      $body .= $line . $nl;
    }
    push @VARCORPUS, $body;
    next if $h->{quoted};
    # An unquoted delimiter: the body is expanded like a "…" string.
    enter();
    push @PATH, 'heredoc';
    my $st2 = new_state($body);
    my $sr2 = $st2->{s};
    my $scratch = { t => '', x => 0, q => 0 };
    while (!at_end($sr2)) {
      if ($$sr2 =~ /\G([^\\\$`]+)/gc) { charge(length $1); next }
      my $c = peek($sr2);
      if ($c eq '\\') { $$sr2 =~ /\G\\.?/gcs; charge(2); next }
      if ($c eq '`') { parse_backtick($st2, 'heredoc'); next }
      dollar($st2, 'heredoc', $scratch, 1);
    }
    pop @PATH;
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
      $j++;
      $j++ if $cl =~ /[oO]\z/;            # -o posix, -O extglob, +o x
      next;
    }
    last;
  }
  return undef unless $seen_c && $j < @$t;
  return $t->[$j];
}

sub process_command {
  my ($words, $ctx) = @_;
  my @t = map { $_->{t} } @$words;
  my @x = map { $_->{x} } @$words;
  print STDERR join('>', @PATH), ': ', join(' ', map { "[$_]" } @t), "\n" if $TRACE;
  # The variable corpus: LITERAL NAME=value assignment values. A value built
  # from an expansion is left out -- `BODY=$(cat <<'EOF' …)` would add the
  # heredoc body a second time, and two Fix-Size lines are a malformed body.
  my $i = 0;
  while ($i < @t && $t[$i] =~ /^[A-Za-z_][A-Za-z0-9_]*=(.*)\z/s) { push @VARCORPUS, $1 unless $x[$i]; $i++ }
  if ($i < @t && $t[$i] =~ /^(?:export|local|declare|readonly|typeset)\z/) {
    for my $j ($i + 1 .. $#t) { push @VARCORPUS, $1 if !$x[$j] && $t[$j] =~ /^[A-Za-z_][A-Za-z0-9_]*=(.*)\z/s }
  }
  for my $k (0 .. $#t) {
    next unless basename_of($t[$k]) eq 'gh';
    my @c  = ('gh', @t[$k + 1 .. $#t]);
    my @cx = (0, @x[$k + 1 .. $#x]);
    if ($k > 0 && $FIND_ACT{ $t[$k - 1] }) {
      for my $e (1 .. $#c) { if ($c[$e] eq ';' || $c[$e] eq '+') { splice @c, $e; splice @cx, $e; last } }
    }
    my $shape = filing_shape(@c);
    next if $shape eq 'none';
    my $f = fields_of($shape, \@c, \@cx);
    push @RECORDS, [$shape, $ctx, $f];
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
  print "gh $GH_VERSION\n";
  print "create-val @CREATE_VAL\ncreate-bool @CREATE_BOOL\napi-val @API_VAL\napi-bool @API_BOOL\n";
  exit 0;
}
$TRACE = 1 if @ARGV && $ARGV[0] eq '--trace';

binmode STDIN; binmode STDOUT;
$SIG{ALRM} = sub { print STDERR "bound=alarm\n"; print "E\0alarm\0"; exit 3 };
alarm $ALARM_S;
my $input = do { local $/; <STDIN> };
$input = '' unless defined $input;
my $ok = eval {
  fail2('NUL byte in input') if index($input, "\0") >= 0;
  $BUDGET = 8 * length($input) + 65536;
  my $st = new_state($input);
  push @PATH, 'top';
  parse_list($st, 'top', 'eof');
  drain_heredocs($st);
  pop @PATH;
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
my $vc = join "\n", @VARCORPUS;
my $out = '';
for my $r (@RECORDS) {
  my ($shape, $ctx, $f) = @$r;
  my @f = @$f;
  push @f, "varcorpus=$vc" if grep { $_ eq 'bodyvar=1' } @f;
  $out .= join("\0", 'F', $shape, $ctx, scalar(@f), @f) . "\0";
}
print $out, "OK\0";
exit 0;
