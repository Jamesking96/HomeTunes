// Every player's fixed setup, in one place (refactor phase 4). These are the exact mpv settings
// each screen or service used to send itself before phase 4.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/engine/engines.dart';

void main() {
  test('each use keeps the mpv settings it always had', () {
    expect(engineSettings(EngineUse.videoPage), isEmpty);
    expect(engineSettings(EngineUse.musicVideo), [('aid', 'no'), ('sid', 'no')]);
    expect(engineSettings(EngineUse.framePicker), [('vid', 'auto'), ('aid', 'no'), ('sid', 'no'), ('hr-seek', 'yes')]);
    expect(engineSettings(EngineUse.probe), [('ao', 'null'), ('sid', 'no')]);
    expect(engineSettings(EngineUse.thumbnails), [('vid', 'auto'), ('aid', 'no'), ('sid', 'no')]);
  });

  test('each use keeps its title (Playback log, sound mixer)', () {
    expect({for (final u in EngineUse.values) u: u.title}, {
      EngineUse.videoPage: 'HomeTunes video',
      EngineUse.musicVideo: 'HomeTunes music video',
      EngineUse.framePicker: 'HomeTunes frame picker',
      EngineUse.probe: 'HomeTunes details',
      EngineUse.thumbnails: 'HomeTunes thumbnails',
    });
  });
}
