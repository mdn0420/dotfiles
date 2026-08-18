{ user, ... }:

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

  system.defaults = {
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
      KeyRepeat = 2;          # fast key repeat
      InitialKeyRepeat = 15;  # short delay before repeat
      _HIHideMenuBar = false;  # auto-hide the menu bar
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
