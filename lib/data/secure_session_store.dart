abstract class SecureSessionStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}
