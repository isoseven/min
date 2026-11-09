{ ... }:

{
  xdg.desktopEntries.vlc = {
    name = "VLC media player";
    genericName = "Media Player";
    comment = "Play movies and songs";
    exec = "vlc --width=1100 --height=750 %U";
    icon = "vlc";
    terminal = false;
    categories = [
      "AudioVideo"
      "Player"
      "Recorder"
    ];
    mimeType = [
      "video/mp4"
      "video/x-matroska"
      "video/webm"
      "audio/mpeg"
      "audio/x-wav"
    ];
  };

  xdg.desktopEntries.vesktop = {
    name = "Vesktop";
    genericName = "Internet Messenger";
    comment = "A cross platform Discord client with less bloat";
    exec = "vesktop --window-size=1400,900 %U";
    icon = "vesktop";
    terminal = false;
    categories = [
      "Network"
      "InstantMessaging"
    ];
  };

  xdg.desktopEntries.obsidian = {
    name = "Obsidian";
    genericName = "Knowledge base";
    comment = "Knowledge base that works on top of local Markdown files";
    exec = "obsidian --window-size=1400,900 %U";
    icon = "obsidian";
    terminal = false;
    categories = [ "Office" ];
    mimeType = [ "x-scheme-handler/obsidian" ];
  };

  xdg.desktopEntries.spotify = {
    name = "Spotify";
    genericName = "Music Player";
    icon = "spotify-client";
    exec = "spotify --window-size=1200,800 %U";
    terminal = false;
    categories = [
      "Audio"
      "Music"
      "Player"
      "AudioVideo"
    ];
    mimeType = [ "x-scheme-handler/spotify" ];
    settings.StartupWMClass = "spotify";
  };
}
