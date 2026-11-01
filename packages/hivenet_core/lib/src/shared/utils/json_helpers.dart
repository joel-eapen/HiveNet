/// Small JSON helpers shared by the hand-written model serializers.
library;

typedef Json = Map<String, Object?>;

String dateToJson(DateTime value) => value.toUtc().toIso8601String();

DateTime dateFromJson(Object? value) {
  if (value is String) return DateTime.parse(value).toUtc();
  throw FormatException('Expected ISO-8601 date string, got: $value');
}

DateTime? optionalDateFromJson(Object? value) =>
    value == null ? null : dateFromJson(value);

String? optionalDateToJson(DateTime? value) =>
    value == null ? null : dateToJson(value);
