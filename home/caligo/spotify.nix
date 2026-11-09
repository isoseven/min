{ inputs, pkgs, ... }:
let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.spicetify = {
    enable = true;
    theme = spicePkgs.themes.text // {
      additionalCss = ''
        :root {
          --border-radius: 0px;
          --global-nav-margin-top: 10px;
        }

        * {
          border-radius: 0 !important;
        }

        .main-topBar-windowControls,
        .main-globalNav-windowControls,
        [class*="windowControls"],
        .Root__globalNav > [class*="drag"]:empty {
          display: none !important;
        }

        .view-homeShortcutsGrid-shortcuts::before {
          content: "♫⋆｡♪ ₊˚♬ ﾟ." !important;
          font-family: var(--font-family) !important;
          font-size: 32px !important;
          line-height: 1.4 !important;
          white-space: nowrap !important;
          letter-spacing: 0.08em !important;
        }

        .main-entityHeader-headerText::before {
          content: "♫⋆｡♪ ₊˚♬ ﾟ." !important;
          font-family: var(--font-family) !important;
        }

        .Root__right-sidebar:not(:has(aside:not(:empty))) {
          border: none !important;
          background: transparent !important;
          width: 0 !important;
          min-width: 0 !important;
          max-width: 0 !important;
          padding: 0 !important;
          margin: 0 !important;
          overflow: hidden !important;
        }

        .Root__right-sidebar:not(:has(aside:not(:empty)))::before {
          content: none !important;
        }

        .progress-bar__fg,
        .x-progressBar-fillColor,
        .x-progressBar-progressBarBg > div > div,
        .main-playbackBarRemainingTime-container ~ div .progress-bar__fg {
          background-color: #e8e8ea !important;
        }

        .progress-bar__bg,
        .x-progressBar-progressBarBg,
        .x-progressBar-sliderArea > div:first-child {
          background-color: rgba(232, 232, 234, 0.12) !important;
        }

        .progress-bar__slider,
        .x-progressBar-slider {
          background-color: #ffffff !important;
          border: none !important;
        }

        .player-controls__buttons button,
        .main-nowPlayingBar-right button,
        .main-playPauseButton,
        .main-skipBackButton,
        .main-skipForwardButton,
        .main-shuffleButton,
        .main-repeatButton,
        .main-genericButton-button,
        .main-addButton-button,
        .Root__globalNav button {
          color: #e8e8ea !important;
          opacity: 1 !important;
        }

        .player-controls__buttons button svg,
        .main-nowPlayingBar-right button svg,
        .Root__globalNav button svg,
        .main-trackList-rowMoreButton svg {
          fill: currentColor !important;
        }

        button[aria-checked="true"],
        .main-shuffleButton-button--active,
        .main-repeatButton-button--active,
        .main-addButton-active {
          color: #ffffff !important;
        }

        button[aria-checked="true"]::after,
        .main-shuffleButton-button--active::after,
        .main-repeatButton-button--active::after {
          background-color: #ffffff !important;
        }

        .x-toggle-indicatorWrapper,
        .x-toggle-bg {
          background-color: rgba(232, 232, 234, 0.22) !important;
        }

        .x-toggle-input:checked + .x-toggle-indicatorWrapper,
        .x-toggle-input:checked + .x-toggle-bg {
          background-color: #e8e8ea !important;
        }

        .x-toggle-indicator {
          background-color: #0b0b0c !important;
        }

        .main-trackList-rowSubTitle,
        .main-cardSubHeader-root,
        .main-entityHeader-subtitle,
        .main-type-mesto,
        .main-type-finale {
          color: #c4c4ca !important;
        }

        .main-playButton-PlayButton,
        .main-card-PlayButtonContainer button,
        [data-testid="play-button"],
        [data-testid="card-play-button"],
        .main-shelf-playButton {
          background-color: transparent !important;
          color: #e8e8ea !important;
          box-shadow: none !important;
          border: none !important;
        }

        :is([class*="card"], [class*="Card"], [class*="shortcut"], [class*="Shortcut"], [class*="tile"], [class*="Tile"], [class*="gridItem"], [class*="trackListRow"]):hover
          :is(.main-playButton-PlayButton, [data-testid="play-button"], [data-testid="card-play-button"]),
        .main-playButton-PlayButton:hover,
        [data-testid="play-button"]:hover,
        [data-testid="card-play-button"]:hover {
          background-color: #ffffff !important;
          color: #0b0b0c !important;
          box-shadow: none !important;
        }

        :is([class*="card"], [class*="Card"], [class*="shortcut"], [class*="Shortcut"], [class*="tile"], [class*="Tile"], [class*="gridItem"], [class*="trackListRow"]):hover
          :is(.main-playButton-PlayButton, [data-testid="play-button"], [data-testid="card-play-button"]) svg,
        .main-playButton-PlayButton:hover svg,
        [data-testid="play-button"]:hover svg,
        [data-testid="card-play-button"]:hover svg {
          fill: #0b0b0c !important;
          color: #0b0b0c !important;
          filter: none !important;
        }

        .main-nowPlayingBar-left {
          display: flex !important;
          align-items: center !important;
        }

        .main-nowPlayingWidget-nowPlaying,
        .main-trackInfo-container {
          display: flex !important;
          align-items: center !important;
          gap: 10px !important;
        }

        .main-trackInfo-container {
          flex-direction: column !important;
          align-items: flex-start !important;
          justify-content: center !important;
          gap: 2px !important;
        }
      '';
    };
    spotifyLaunchFlags = "--transparent-window-controls --window-size=1200,800";
    colorScheme = "custom";
    customColorScheme = {
      text = "e8e8ea";
      subtext = "c4c4ca";
      main = "0b0b0c";
      main-elevated = "151517";
      highlight = "232328";
      highlight-elevated = "2c2c32";
      sidebar = "0b0b0c";
      player = "151517";
      card = "151517";
      shadow = "000000";
      selected-row = "e8e8ea";
      button = "e8e8ea";
      button-active = "ffffff";
      button-disabled = "72727a";
      tab-active = "27272c";
      notification = "151517";
      notification-error = "c14545";
      misc = "c4c4ca";
      equalizer = "e8e8ea";
      border-active = "e8e8ea";
      border-inactive = "7a7a82";
    };
    enabledExtensions = with spicePkgs.extensions; [
      adblock
      hidePodcasts
      shuffle
    ];
  };
}
