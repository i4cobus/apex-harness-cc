# Split a shell command line into sub-commands, on separators that are actually separators.
# Shared by env-guard.sh and fs-guard.sh; both judge each fragment by its leading program,
# so a fragment boundary in the wrong place changes the verdict.
#
# The naive version split on every  & | ; ( ) { } `  and newline, quoted or not, on the
# theory that over-splitting can only drop a trigger, never create one. That is false: it
# promotes a quoted word to the front of a fragment, and a commit message mentioning an
# install inside parentheses was blocked as a dependency install. Observed twice within
# minutes of first real use.
#
# Rules, matching what a shell actually does:
#   single quotes  - nothing is special until the closing quote
#   double quotes  - separators are literal text, but $( and a backtick still start a
#                    command substitution, so those must split (else quoting a command
#                    substitution would be a silent bypass)
#   unquoted       - every separator splits
# A backslash escapes the next character everywhere except inside single quotes.
#
# Heredocs: a body is shell to be executed only when the heredoc feeds a shell. Fed to
# anything else it is inert data — a file being written, a script in another language —
# and scanning it blocked documents whose *content* was install instructions. So the body
# is dropped unless the owning fragment's leading program is a shell, in which case it is
# kept and split as usual. Quoting the delimiter (<< 'EOF') changes expansion, not who
# executes it, so it does not affect this. Residual gap: a non-shell command that runs its
# stdin as shell (nothing in SHELLS below) hides its body from the scan.

function basename(p,   k) { k = split(p, _b, "/"); return _b[k] }

# Leading program of a fragment, looking past sudo/env-style wrappers.
function lead(frag,   w, m, j, t) {
  m = split(frag, w, /[ \t]+/)
  for (j = 1; j <= m; j++) {
    t = w[j]
    if (t == "") continue
    if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) continue          # VAR=val prefix
    t = basename(t)
    if (t ~ /^(sudo|env|command|exec|nohup|time|nice|stdbuf)$/) continue
    if (t ~ /^-/) continue                                 # flags of a wrapper
    return t
  }
  return ""
}

function is_shell(frag,   t) {
  t = lead(frag)
  return (t ~ /^(sh|bash|dash|ksh|zsh|csh|tcsh|fish|ash|busybox)$/)
}

{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  n = length(buf); out = ""; q = ""; i = 1
  fstart = 1        # index in `out` where the current fragment begins
  npend = 0         # heredocs opened on this line, bodies not yet consumed
  while (i <= n) {
    c = substr(buf, i, 1)
    if (q == "'") {
      out = out c; if (c == "'") q = ""; i++; continue
    }
    if (q == "\"") {
      if (c == "$" && substr(buf, i+1, 1) == "(") { out = out "\n"; fstart = length(out) + 1; i += 2; continue }
      if (c == "`")  { out = out "\n"; fstart = length(out) + 1; i++; continue }
      if (c == "\\") { out = out substr(buf, i, 2); i += 2; continue }
      out = out c; if (c == "\"") q = ""; i++; continue
    }
    if (c == "'" || c == "\"") { q = c; out = out c; i++; continue }
    if (c == "\\") { out = out substr(buf, i, 2); i += 2; continue }

    # heredoc opener: << or <<- , but not the <<< herestring
    if (c == "<" && substr(buf, i+1, 1) == "<" && substr(buf, i+2, 1) != "<") {
      out = out "<<"; i += 2
      dash = 0
      if (substr(buf, i, 1) == "-") { dash = 1; out = out "-"; i++ }
      while (i <= n && (substr(buf, i, 1) == " " || substr(buf, i, 1) == "\t")) { out = out substr(buf, i, 1); i++ }
      delim = ""
      while (i <= n) {
        d = substr(buf, i, 1)
        if (d == "'" || d == "\"") {                       # quoted delimiter
          endq = d; out = out d; i++
          while (i <= n && substr(buf, i, 1) != endq) { delim = delim substr(buf, i, 1); out = out substr(buf, i, 1); i++ }
          if (i <= n) { out = out endq; i++ }
          break
        }
        if (d == " " || d == "\t" || d == "\n" || index("&|;(){}`<>", d) > 0) break
        if (d == "\\") { i++; if (i <= n) { delim = delim substr(buf, i, 1); out = out substr(buf, i, 1); i++ }; continue }
        delim = delim d; out = out d; i++
      }
      if (delim != "") {
        npend++
        pdelim[npend] = delim
        pdash[npend]  = dash
        pkeep[npend]  = is_shell(substr(out, fstart))
      }
      continue
    }

    if (index("&|;(){}`\n", c) > 0) {
      out = out "\n"
      i++
      if (c == "\n" && npend > 0) {
        for (h = 1; h <= npend; h++) {
          while (i <= n) {
            eol = index(substr(buf, i), "\n")
            if (eol == 0) { line = substr(buf, i); nexti = n + 1 }
            else          { line = substr(buf, i, eol - 1); nexti = i + eol }
            t = line
            if (pdash[h]) sub(/^\t+/, "", t)
            i = nexti
            if (t == pdelim[h]) break
            if (pkeep[h]) out = out line "\n"
          }
        }
        npend = 0
      }
      fstart = length(out) + 1
      continue
    }
    out = out c; i++
  }
  print out
}
