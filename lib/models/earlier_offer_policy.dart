/// Prototype session configuration; replace with approved facility settings in live mode.
class EarlierOfferPolicy {
  final int openingHour;
  final int closingHour;
  final int slotMinutes;
  final Duration responseWindow;
  final Set<int> weekdays;
  const EarlierOfferPolicy({
    this.openingHour = 9,
    this.closingHour = 12,
    this.slotMinutes = 15,
    this.responseWindow = const Duration(hours: 24),
    this.weekdays = const {1, 2, 3, 4, 5},
  });

  Iterable<DateTime> slots(DateTime from) sync* {
    if (slotMinutes <= 0 || closingHour <= openingHour) return;
    final day = DateTime(from.year, from.month, from.day);
    for (var offset = 0; offset < 14; offset++) {
      final date = day.add(Duration(days: offset));
      if (!weekdays.contains(date.weekday)) continue;
      for (
        var minute = openingHour * 60;
        minute < closingHour * 60;
        minute += slotMinutes
      ) {
        yield DateTime(
          date.year,
          date.month,
          date.day,
          minute ~/ 60,
          minute % 60,
        );
      }
    }
  }
}
