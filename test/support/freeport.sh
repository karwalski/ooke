# test/support/freeport.sh — sourced by the shell tests that start a server.
# Story 127.560.
#
# The tests used to pick a port by arithmetic on the shell's PID
# (20000 + $$ % 20000, sometimes plus an offset) and never checked it was
# free. When another program already listened there (on 2026-11-28 a VS Code
# helper on 127.0.0.1:30869) the server could not bind, and the test failed
# as if ooke were broken -- or, for a test that only polls with curl, could
# talk to the other program instead.
#
#   freeport   print a TCP port on 127.0.0.1 that nothing is bound to: bind
#              port 0, read back the port the kernel chose, close it. The
#              window between this and the server's own bind is short but not
#              zero, so a test that must not flake can also retry on
#              "Address already in use" (test/serve/compile_app.sh does).
#
# Without python3 it falls back to probing PID-derived ports with curl and
# skipping any that accept a connection (curl exit 7 = connection refused);
# a port a server still holds is skipped, so sequential calls do not collide.
freeport() {
  if command -v python3 >/dev/null 2>&1; then
    python3 -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
' && return 0
  fi
  _fp_n=0
  while [ "$_fp_n" -lt 200 ]; do
    _fp_p=$(( 20000 + (($$ + _fp_n * 7919) % 20000) ))
    _fp_n=$((_fp_n + 1))
    curl -s --max-time 1 -o /dev/null "http://127.0.0.1:$_fp_p/" 2>/dev/null
    if [ $? -eq 7 ]; then echo "$_fp_p"; return 0; fi
  done
  echo "freeport: no free port found" >&2
  return 1
}
