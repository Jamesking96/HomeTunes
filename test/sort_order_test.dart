// Ascending / descending for every sort (0.1.69): the words for each kind of sort, where each
// starts, and turning lists and headed groups round.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/state/sort_order.dart';
import 'package:hometunes/state/video_filters.dart';

void main() {
  test('words and starting direction', () {
    expect(SortWords.text.words, ('A to Z', 'Z to A'));
    expect(SortWords.date.words, ('Oldest first', 'Newest first'));
    expect(SortWords.length.words, ('Shortest first', 'Longest first'));
    expect([for (final w in SortWords.values) if (w.startsDescending) w],
        [SortWords.date, SortWords.number, SortWords.length]);
    // Every video and collection sort has words.
    expect(videoSortWords(VideoSort.season), SortWords.order);
    expect(collectionSortWords(CollectionSort.mostVideos), SortWords.number);
  });

  test('turning round: lists, and headed groups with what\'s in them', () {
    expect(reversedIf(false, [1, 2, 3]), [1, 2, 3]);
    expect(reversedIf(true, [1, 2, 3]), [3, 2, 1]);
    final groups = [('A', [1, 2]), (null, [3]), ('C', [4, 5])];
    expect(reverseGroupsIf(false, groups), same(groups));
    expect([for (final (h, l) in reverseGroupsIf(true, groups)) '$h:${l.join(',')}'], ['C:5,4', 'null:3', 'A:2,1']);
  });
}
