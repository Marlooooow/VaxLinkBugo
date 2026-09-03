class MockScenarioClock {
  static final DateTime today = _dateOnly(DateTime.now());

  static DateTime daysAgo(int days) => today.subtract(Duration(days: days));

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
