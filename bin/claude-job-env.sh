# Shared Claude auth for UNATTENDED jobs. SOURCE this file, never execute it.
#
# WHY THIS EXISTS — found on the original machine eight days before it would have bitten.
#
# Every scheduled job authenticated with the same interactive claude.ai login out of
# the login Keychain. None of the plists set a token. That login has a HARD EXPIRY
# which renewing does NOT move. Check yours:
#
#     claude auth status   ->  look for "loginExpiresAt"
#
# When it lapses the CLI returns, verbatim:
#   "Failed to authenticate: this login reached its time limit and cannot be renewed.
#    Run `claude auth login` to sign in again, or use `claude setup-token` and set
#    CLAUDE_CODE_OAUTH_TOKEN for unattended jobs"
#
# So EVERY scheduled job sharing that login stops on the same morning, silently, and
# the only visible symptom is nothing happening. That is the worst kind of outage:
# no error, no alert, just a machine that quietly stopped working for you.
#
# WHY IT IS NOT JUST EXPORTED IN ~/.zshenv, which would be one line instead of this:
# a token session runs at REDUCED SCOPE. From the binary's own string:
#   "env-var and setup-token sessions default to user:inference only"
# Exporting it globally would quietly downgrade your interactive sessions too.
# So it is set per unattended job, and interactive shells keep the full-scope Keychain
# login. Two different jobs, two different credentials, on purpose.
#
# ROTATING IT IS ONE FILE EDIT. Put the token in the file named below. No plist edits,
# no launchctl reloads, nothing to remember in eight places.
#
#   1. Run:  claude setup-token
#   2. Paste the token into the file named below (chmod 600). NEVER into a note,
#      a doc, or this repo.
#   3. Done. Every job that sources this file picks it up on its next run.
#
# This file is a NO-OP while that token file is missing or empty, so it is safe to wire
# up before the token exists — which is exactly how it was installed.

_lefty_tok_file="${LEFTY_OAUTH_TOKEN_FILE:-$HOME/.claude-oauth-token}"
if [ -r "$_lefty_tok_file" ]; then
  _lefty_tok="$(tr -d ' \t\r\n' < "$_lefty_tok_file" 2>/dev/null)"
  if [ -n "$_lefty_tok" ]; then
    export CLAUDE_CODE_OAUTH_TOKEN="$_lefty_tok"
  fi
  unset _lefty_tok
fi
unset _lefty_tok_file
