
import 'package:flutter/widgets.dart';

abstract class ConfigField<T> {
  static ConfigField? parse(dynamic jsonEntry) {
    final String type = jsonEntry['type'];
    final String name = jsonEntry['name'];
    final String label = jsonEntry['label'];
    switch (type) {
      case StringField.type: return StringField(name, label);
      case PasswordField.type: return PasswordField(name, label);
      case LongIntegerField.type: return LongIntegerField(name, label);
      case ColorField.type: return ColorField(name, label, Color(jsonEntry['default']));
    }
    return null;
  }

  final String name;
  final String label;

  ConfigField(this.name, this.label);

  String encodeValue(T value) => value.toString();
}

class StringField extends ConfigField<String> {
  static const type = "String";
  StringField(String name, String label) : super(name, label);
}

class PasswordField extends ConfigField<String> {
  static const type = "Password";
  PasswordField(String name, String label) : super(name, label);
}

class LongIntegerField extends ConfigField<int> {
  static const type = "LongInteger";
  LongIntegerField(String name, String label) : super(name, label);
}

class ColorField extends ConfigField<Color> {
  static const type = "Color";
  ColorField(String name, String label, this.defaultColor) : super(name, label);

  final Color defaultColor;
  @override
  String encodeValue(Color value) => '#' + value.value.toRadixString(16);
}