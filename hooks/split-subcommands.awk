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
{ buf = buf (NR > 1 ? "\n" : "") $0 }
END {
  n = length(buf); out = ""; q = ""; i = 1
  while (i <= n) {
    c = substr(buf, i, 1)
    if (q == "'") {
      out = out c; if (c == "'") q = ""; i++; continue
    }
    if (q == "\"") {
      if (c == "$" && substr(buf, i+1, 1) == "(") { out = out "\n"; i += 2; continue }
      if (c == "`")  { out = out "\n"; i++; continue }
      if (c == "\\") { out = out substr(buf, i, 2); i += 2; continue }
      out = out c; if (c == "\"") q = ""; i++; continue
    }
    if (c == "'" || c == "\"") { q = c; out = out c; i++; continue }
    if (c == "\\") { out = out substr(buf, i, 2); i += 2; continue }
    if (index("&|;(){}`\n", c) > 0) { out = out "\n"; i++; continue }
    out = out c; i++
  }
  print out
}
