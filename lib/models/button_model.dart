class ButtonModel {
  final String name;
  final String? icon;
  final String? phone;
  final String? url;
  final bool visible;
  final List<ButtonModel>? subButtons;
  final int order;

  ButtonModel({
    required this.name,
    required this.icon,
    this.phone,
    this.url,
    required this.visible,
    this.subButtons,
    required this.order,
  });

  factory ButtonModel.fromMap(Map<String, dynamic> map) {
    //print('Mapa recibido: $map'); // Imprime el mapa para depurar

    return ButtonModel(
      name: map['name'] as String,
      icon: map['icon'] as String?,
      phone: map['phone'] as String?,
      url: map['url'] as String?,
      visible: map['visible'] as bool,
      subButtons: map['subButtons'] != null
          ? List<Map<String, dynamic>>.from(map['subButtons'] as List).map((e) => ButtonModel.fromMap(e)).toList()
          : null,
      order: map['order'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'icon': icon,
      'phone': phone,
      'url': url,
      'visible': visible,
      'subButtons': subButtons?.map((e) => e.toMap()).toList(),
      'order': order,
    };
  }
}
