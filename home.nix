{ config, pkgs, user, ... }:

let
  dotfiles = "${config.home.homeDirectory}/.dotfiles";
in

{
  home.username = user;
  home.homeDirectory = "/Users/${user}";
  home.stateVersion = "24.11";
  home.packages = with pkgs; [
    # cli i use constantly
    ripgrep   # fast search
    fd        # fast find
    fzf       # fuzzy finder
    jq        # json on the command line
    gh        # github cli; extensions still live in ~/.local/share/gh
    lazygit
    neovim
    fnm       # node version manager; the zsh cd-hook needs it on PATH, not just in initContent
    go        # toolchain; nix sets GOROOT, so never set it by hand
    mosh      # ssh that survives roaming and sleep
    postgresql # psql/pg_dump client; ships the server binaries too, but nothing runs them
    # the font everything renders in
    nerd-fonts.hack
  ];
  fonts.fontconfig.enable = true;
  home.sessionVariables.EDITOR = "nvim";

  # Binaries from `go install` land in $GOPATH/bin (~/go/bin by default).
  # nix-darwin's /etc/zshenv builds PATH itself and never runs path_helper, so
  # /etc/paths.d entries are ignored - anything extra has to be declared here.
  home.sessionPath = [ "${config.home.homeDirectory}/go/bin" ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;      # ghost text from history
    syntaxHighlighting.enable = true;  # commands turn green when valid
    initContent = ''
      bindkey '^f' autosuggest-accept

      # Switches node on cd when a .nvmrc, .node-version, or package.json says to.
      eval "$(${pkgs.fnm}/bin/fnm env --use-on-cd --shell zsh)"

      # Completed TickTick tasks, scoped to the UTM project. A function, not an
      # alias, so the project filter lands after any flags I pass.
      ticktick-utm() { ticktick-completed "$@" --projects 69ccd90f; }
    '';
    shellAliases = {
      ".." = "cd ..";
      add = "git add .";
      push = "git push";
      pull = "git pull";
      gs = "git status";
      claude-personal = "CLAUDE_CONFIG_DIR=~/.claude ${config.home.homeDirectory}/.local/bin/claude";
      claude-utm = "CLAUDE_CONFIG_DIR=~/.claude-utm ${config.home.homeDirectory}/.local/bin/claude";
      claude = "echo 'Use specific commands: claude-personal or claude-utm'";
      subl = "open '/Applications/Sublime Text.app'";
    };
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      format = "$directory$git_branch$git_status$cmd_duration$line_break$character";
      character = {
        success_symbol = "[❯](purple)";
        error_symbol = "[❯](red)";
      };
      cmd_duration.format = "[$duration]($style) ";
    };
  };

  # Edit-in-place: the real file stays in my repo, ~/.config just points at it.
  home.file.".config/nvim".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/nvim";
  home.file.".config/herdr".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.config/herdr";
  home.file.".claude/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/settings.json";
  home.file.".claude/statusline-command.sh".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.claude/statusline-command.sh";

  # Keep Pi's credential and runtime state local by linking only authored files and directories.
  home.file.".pi/agent/themes".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/themes";
  home.file.".pi/agent/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/extensions";
  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/models.json";
  home.file.".pi/agent/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.pi/agent/settings.json";

  home.file.".claude/CLAUDE.md".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/AGENTS.md";

  # Authored skills live once under ~/.agents/skills, the vendor-neutral location
  # third-party skill installers already use. Each agent reads its own directory,
  # so every tool that should see a skill needs its own link to the same source.
  home.file.".agents/skills/run-markdown-server".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/run-markdown-server";
  home.file.".claude/skills/run-markdown-server".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/home/.agents/skills/run-markdown-server";
}
