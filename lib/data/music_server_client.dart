import 'dart:io';

import '../domain/audio_track.dart';

/// Operations the Pulse library needs from a remote music server.
/// Server-specific IDs remain scoped by the account fingerprint in the controller.
abstract class MusicServerClient {
  String? get token;
  set token(String? value);
  Set<String> get favoriteIds;

  Future<Map<String, dynamic>> authenticate(String user, String password);
  Future<Map<String, dynamic>> initiateQuickConnect();
  Future<bool> quickConnectAuthorized(String secret);
  Future<Map<String, dynamic>> authenticateQuickConnect(String secret);
  Future<Map<String, dynamic>> currentUser();
  Future<List<AudioTrack>> audioItems(String userId);
  Future<List<Map<String, dynamic>>> artists(String userId);
  Future<List<Map<String, dynamic>>> playlists(String userId);
  Future<List<String>> playlistItemIds(String playlistId, String userId);
  Future<String> createPlaylist(
      String name, String userId, List<String> itemIds);
  Future<void> addPlaylistItems(
      String playlistId, String userId, List<String> itemIds);
  Future<void> updatePlaylist(String playlistId,
      {String? name, List<String>? itemIds});
  Future<void> deletePlaylist(String playlistId);
  Future<void> setFavorite(String itemId, String userId, bool favorite);
  Future<dynamic> request(String method, String path,
      {Map<String, String>? query, Object? body});
  Future<HttpClientResponse> openAudio(String itemId, String? range,
      {String? userId, String method = 'GET'});
  Future<HttpClientResponse> openDownload(String itemId, {String? userId});
  Future<HttpClientResponse> openImage(String itemId);
  Future<HttpClientResponse> openUserImage(String userId);
  void close();
}
