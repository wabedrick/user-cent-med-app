class Equipment {
  final String id;
  final String name;
  final String model;
  final String manufacturer;
  final String manualPdfUrl;
  final String videoTutorialUrl;

  Equipment({
    required this.id,
    required this.name,
    required this.model,
    required this.manufacturer,
    required this.manualPdfUrl,
    required this.videoTutorialUrl,
  });

  factory Equipment.fromMap(String id, Map<String, dynamic> data) {
    return Equipment(
      id: id,
      name: data['name'] ?? '',
      model: data['model'] ?? '',
      manufacturer: data['manufacturer'] ?? '',
      manualPdfUrl: data['manualPdfUrl'] ?? '',
      videoTutorialUrl: data['videoTutorialUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'model': model,
      'manufacturer': manufacturer,
      'manualPdfUrl': manualPdfUrl,
      'videoTutorialUrl': videoTutorialUrl,
    };
  }
}
