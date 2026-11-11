import 'package:flutter_test/flutter_test.dart';
import 'package:agentphone/domain/product_repository.dart';

void main() {
  test('server upgrade accepts only exact semantic versions', () {
    expect(isExactServerVersion('2.0.29'), isTrue);
    expect(isExactServerVersion('2.0.29-beta.2+mobile'), isTrue);
    expect(isExactServerVersion('latest'), isFalse);
    expect(isExactServerVersion('2.0'), isFalse);
    expect(isExactServerVersion(' 2.0.29'), isFalse);
  });
}
