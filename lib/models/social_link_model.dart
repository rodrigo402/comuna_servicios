class SocialLink {
  final String platform;
  final String url;
  final String icon;
  final bool visible;
  final int? order;

  SocialLink({
    required this.platform,
    required this.url,
    required this.icon,
    required this.visible,
    this.order,
  });

  factory SocialLink.fromMap(Map<String, dynamic> map) {
    return SocialLink(
      platform: map['platform'] ?? '',
      url: map['url'] ?? '',
      icon: map['icon'] ?? '',
      visible: map['visible'] ?? false,
      order: map['order'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'platform': platform,
      'url': url,
      'icon': icon,
      'visible': visible,
      'order': order,
    };
  }
}
