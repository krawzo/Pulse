enum PulseDestination {
  library,
  tracks,
  albums,
  artists,
  favorites,
  playlists,
  jellyfin,
  settings
}

PulseDestination compactDestination(int index) => switch (index) {
      1 => PulseDestination.favorites,
      2 => PulseDestination.playlists,
      _ => PulseDestination.library,
    };

int rootIndex(PulseDestination destination) => switch (destination) {
      PulseDestination.favorites => 1,
      PulseDestination.playlists => 2,
      _ => 0,
    };
