{ pkgs, ... }:

let
  sudo = "/run/wrappers/bin/sudo";
  grep = "${pkgs.gnugrep}/bin/grep";
  gdb = "${pkgs.gdb}/bin/gdb";

  osi = pkgs.writeShellApplication {
    name = "osi";
    runtimeInputs = [
      pkgs.procps
      pkgs.coreutils
    ];
    text = ''
      lib="$HOME/Projects/osiris-csgo/build/Source/libOsiris.so"

      if [ ! -f "$lib" ]; then
        echo "libOsiris.so not found at $lib"
        exit 1
      fi

      ${sudo} -v

      if ! pid=$(pidof -s csgo_linux64); then
        echo "waiting for csgo_linux64..."
        until pid=$(pidof -s csgo_linux64); do sleep 1; done
      fi

      if ! ${sudo} ${grep} -q client_client.so "/proc/$pid/maps"; then
        echo "waiting for the game to load..."
        until ${sudo} ${grep} -q client_client.so "/proc/$pid/maps"; do sleep 1; done
        sleep 10
      fi

      if ${sudo} ${grep} -q libOsiris.so "/proc/$pid/maps"; then
        echo "already injected into $pid"
        exit 0
      fi

      out=$(${sudo} ${gdb} -batch -p "$pid" \
        -ex "set sysroot /proc/$pid/root" \
        -ex "call (void*)dlopen(\"$lib\", 2)" \
        -ex "call (char*)dlerror()" 2>&1 | tail -2) || true

      if ${sudo} ${grep} -q libOsiris.so "/proc/$pid/maps"; then
        echo "injected into $pid, press Insert"
      else
        echo "injection failed:"
        echo "$out"
        exit 1
      fi
    '';
  };
in
{
  home.packages = [ osi ];
}
