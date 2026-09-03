class GuardianRelationshipOptions {
  static const sexes = ['Female', 'Male'];
  static const female = [
    'Mother',
    'Grandmother',
    'Aunt',
    'Sister',
    'Legal Guardian',
  ];
  static const male = [
    'Father',
    'Grandfather',
    'Uncle',
    'Brother',
    'Legal Guardian',
  ];

  static List<String> forSex(String sex) => sex == 'Male' ? male : female;
  static String defaultForSex(String sex) =>
      sex == 'Male' ? 'Father' : 'Mother';
  static String sexForRelationship(String relationship) =>
      male.contains(relationship) ? 'Male' : 'Female';
}
