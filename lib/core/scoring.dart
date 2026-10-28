/// Stars, coin rewards, booster prices and spoiler-free share text.
library;

const int kStartingCoins = 150;
const int kMaxLives = 4;
const int kPairMagnetCost = 30;
const int kCategoryPeekCost = 40;
const int kExtraLifeCost = 60;
const int kPracticeReward = 5;
const int kDailyBonus = 25;

/// Stars depend only on actual wrong submissions, never on lives left.
int starsForMistakes(int mistakes) {
  if (mistakes <= 0) return 3;
  if (mistakes <= 2) return 2;
  return 1;
}

/// Coins for the first win of a level (campaign or daily, before bonus).
int firstWinReward(int stars) => switch (stars) {
  3 => 50,
  2 => 30,
  _ => 15,
};

const List<String> tierEmoji = ['🟨', '🟩', '🟦', '🟪'];

String campaignShareHeader(String packTitle, int levelNumber) =>
    'LexiStack · $packTitle #$levelNumber';

String dailyShareHeader(String date) => 'LexiStack · Daily $date';

/// Builds the spoiler-free result grid: no tile words, titles or trivia.
/// [rows] holds the true tier (1-4) of each tile of every evaluated guess,
/// in the order the tiles were selected.
String buildShareText({
  required String header,
  required bool won,
  required int mistakes,
  required int groupsSolved,
  required List<List<int>> rows,
}) {
  final mistakeText = '$mistakes ${mistakes == 1 ? 'mistake' : 'mistakes'}';
  final stars = starsForMistakes(mistakes);
  final second = won
      ? '${'★' * stars}${'☆' * (3 - stars)} · $mistakeText'
      : '$groupsSolved/4 groups · $mistakeText';
  return [
    header,
    second,
    for (final r in rows) r.map((t) => tierEmoji[t - 1]).join(),
  ].join('\n');
}
