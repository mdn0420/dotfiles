{ pkgs, user, ... }:

{
  # Determinate already manages the Nix daemon, so nix-darwin shouldn't.
  nix.enable = false;

  nixpkgs.config.allowUnfree = true;
  nixpkgs.hostPlatform = "aarch64-darwin"; # use x86_64-darwin for Intel CPU

  system.primaryUser = user;
  users.users.${user} = {
    home = "/Users/${user}";
  };
  system.stateVersion = 6;

  # Fingerprint instead of a password for sudo, incl. `sudo darwin-rebuild switch`.
  # nix-darwin owns /etc/pam.d/sudo_local, so this survives macOS updates.
  security.pam.services.sudo_local.touchIdAuth = true;

  # Remote Login. This is what `mosh` rides in on: it bootstraps the session
  # over ssh, then hands off to its own UDP channel.
  services.openssh.enable = true;

  # macOS' application firewall only lets listed binaries accept incoming
  # connections, and "automatically allow signed software" never covers the
  # Nix store, whose binaries are only ad-hoc signed. So mosh-server has to be
  # listed by hand or inbound mosh sessions hang after the ssh handshake.
  # Its store path moves on every mosh update, hence the re-add plus the sweep
  # of entries left behind by older builds.
  system.activationScripts.postActivation.text = ''
    echo "allowing mosh-server through the application firewall..." >&2
    fw=/usr/libexec/ApplicationFirewall/socketfilterfw
    moshServer='${pkgs.mosh}/bin/mosh-server'
    # `|| true` because both greps exit non-zero when there is nothing to sweep,
    # and the activation script runs under `set -e -o pipefail`.
    stale=$("$fw" --listapps \
      | grep -o '/nix/store/[^ ]*/bin/mosh-server' \
      | grep -vxF "$moshServer" || true)
    if [ -n "$stale" ]; then
      echo "$stale" | while read -r path; do "$fw" --remove "$path" >/dev/null; done
    fi
    "$fw" --add "$moshServer" >/dev/null
    "$fw" --unblockapp "$moshServer" >/dev/null
  '';

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = false;  # keep the menu bar visible on the desktop
      AppleShowAllExtensions = true;
    };
    dock.autohide = true;
    finder.FXPreferredViewStyle = "Nlsv";  # list view by default
    finder.CreateDesktop = false;          # clean desktop
    trackpad.Clicking = true;              # tap to click
  };
  nix-homebrew = {
    enable = true;
    inherit user;
    autoMigrate = true;
  };
  homebrew = {
    enable = true;
    onActivation.cleanup = "zap";  # remove anything not listed here
    onActivation.autoUpdate = true;
    onActivation.extraFlags = [ "--force" ];
    taps = [
      { name = "heroku/brew"; trusted = true; }
      { name = "mongodb/brew"; trusted = true; }
    ];
    brews = [
      "herdr"
      "tmux"
      "heroku/brew/heroku"
      # keeps mongod able to read the existing /opt/homebrew/var/mongodb data
      "mongodb/brew/mongodb-community"
      "mongodb/brew/mongodb-database-tools"
      # powershell moved from a cask to a homebrew-core formula; the old cask
      # token 404s on the API, which aborts activation.
      "powershell"
    ];
    casks = [
      "ghostty"
      "opensuperwhisper"
    ];
  };
}
