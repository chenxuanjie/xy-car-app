abstract interface class Transport {
  Future<void> open(Uri uri);
  Stream<String> get stream;
  void send(String data);
  Future<void> close();
}
