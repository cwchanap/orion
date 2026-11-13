import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/game/assets/game_sprite_sheet.dart';
import 'package:orion/game/components/board_component.dart';
import 'package:orion/game/models/game_models.dart';
import 'package:orion/game/rules/board_layout.dart';

Path _line(double length) => Path()
  ..moveTo(0, 0)
  ..lineTo(length, 0);

double _totalLength(Path path) =>
    path.computeMetrics().fold<double>(0, (sum, metric) => sum + metric.length);

Future<Image> _rasterize(
  int width,
  int height,
  void Function(Canvas) draw,
) async {
  final recorder = PictureRecorder();
  draw(Canvas(recorder));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<List<int>> _rgbaAt(Image image, int x, int y) async {
  final data = await image.toByteData(format: ImageByteFormat.rawRgba);
  final index = (y * image.width + x) * 4;
  return [
    data!.getUint8(index),
    data.getUint8(index + 1),
    data.getUint8(index + 2),
    data.getUint8(index + 3),
  ];
}

Future<Image> _uploadMarker(Uint8List pixels, int width, int height) {
  final result = Completer<Image>();
  decodeImageFromPixels(
    pixels,
    width,
    height,
    PixelFormat.rgba8888,
    result.complete,
  );
  return result.future;
}

class _MarkerSheetProbe implements GameSpriteSheet {
  _MarkerSheetProbe(
    this.delegate, {
    this.failOnce = false,
    this.alwaysFail = false,
    this.failSprite = GameSprite.spawnGate,
    this.failLookup = 1,
  });

  final GameSpriteSheet delegate;
  bool failOnce;
  final bool alwaysFail;
  final GameSprite failSprite;
  final int failLookup;
  int matchingLookups = 0;
  final List<GameSprite> calls = [];

  @override
  Sprite sprite(GameSprite sprite) {
    calls.add(sprite);
    if (sprite == failSprite) matchingLookups++;
    if (sprite == failSprite &&
        (alwaysFail || (failOnce && matchingLookups == failLookup))) {
      failOnce = false;
      throw StateError('transient marker lookup failure');
    }
    return delegate.sprite(sprite);
  }
}

class _DecoderAttempt {
  final started = <MarkerDecoderStage>[];
  final acquired = <MarkerDecoderStage, Object>{};
  final disposed = <(MarkerDecoderStage, Object)>[];
  bool failed = false;
}

class _DecoderProbe implements MarkerDecoderProbe {
  _DecoderProbe({
    required this.failureStage,
    required this.failingAttempts,
    this.holdFirstFrame = false,
  });

  final MarkerDecoderStage failureStage;
  final Set<int> failingAttempts;
  final bool holdFirstFrame;
  final attempts = <_DecoderAttempt>[];
  final frameReady = Completer<FrameInfo>();
  final releaseFrame = Completer<void>();

  @override
  Future<T> run<T>(
    MarkerDecoderStage stage,
    Future<T> Function() operation,
  ) async {
    if (stage == MarkerDecoderStage.buffer) attempts.add(_DecoderAttempt());
    final attempt = attempts.last;
    attempt.started.add(stage);
    if (stage == failureStage && failingAttempts.contains(attempts.length)) {
      await Future<void>.delayed(Duration.zero);
      attempt.failed = true;
      throw StateError('injected ${stage.name} decode failure');
    }
    final resource = await operation();
    attempt.acquired[stage] = resource as Object;
    if (stage == MarkerDecoderStage.frame &&
        holdFirstFrame &&
        !frameReady.isCompleted) {
      frameReady.complete(resource as FrameInfo);
      await releaseFrame.future;
    }
    return resource;
  }

  @override
  void didDispose(MarkerDecoderStage stage, Object resource) {
    final attempt = attempts.lastWhere(
      (attempt) => identical(attempt.acquired[stage], resource),
    );
    attempt.disposed.add((stage, resource));
  }
}

class _DecoderFailureCase {
  const _DecoderFailureCase(
    this.name,
    this.failingAttempts,
    this.bakeSprites,
    this.failures,
  );

  final String name;
  final Set<int> failingAttempts;
  final List<GameSprite> bakeSprites;
  final List<(GameSprite, int)> failures;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const decoderCases = [
    _DecoderFailureCase(
      'transient spawn',
      {1},
      [GameSprite.spawnGate, GameSprite.spawnGate, GameSprite.baseReactor],
      [(GameSprite.spawnGate, 1)],
    ),
    _DecoderFailureCase(
      'transient core',
      {2},
      [GameSprite.spawnGate, GameSprite.baseReactor, GameSprite.baseReactor],
      [(GameSprite.baseReactor, 1)],
    ),
    _DecoderFailureCase(
      'persistent spawn',
      {1, 2},
      [GameSprite.spawnGate, GameSprite.spawnGate, GameSprite.baseReactor],
      [(GameSprite.spawnGate, 1), (GameSprite.spawnGate, 2)],
    ),
    _DecoderFailureCase(
      'persistent both markers',
      {1, 2, 3, 4},
      [
        GameSprite.spawnGate,
        GameSprite.spawnGate,
        GameSprite.baseReactor,
        GameSprite.baseReactor,
      ],
      [
        (GameSprite.spawnGate, 1),
        (GameSprite.spawnGate, 2),
        (GameSprite.baseReactor, 1),
        (GameSprite.baseReactor, 2),
      ],
    ),
  ];

  for (final stage in MarkerDecoderStage.values) {
    for (final failureCase in decoderCases) {
      for (final startFromRender in [false, true]) {
        test('decoder stage ${stage.name}: ${failureCase.name} from '
            '${startFromRender ? 'render' : 'onMount'}', () async {
          final source = await Flame.images.load(GameSpriteSheet.fileName);
          final sheet = _MarkerSheetProbe(GameSpriteSheet.fromImage(source));
          final probe = _DecoderProbe(
            failureStage: stage,
            failingAttempts: failureCase.failingAttempts,
          );
          final diagnostics = <String>[];
          final uncaught = <Object>[];
          final previousDebugPrint = debugPrint;
          debugPrint = (message, {wrapWidth}) {
            if (message != null) diagnostics.add(message);
          };
          final board = BoardComponent(
            cellSize: 20,
            pathCells: BoardLayout.pathCells,
            spriteSheet: sheet,
            markerDecoderProbe: probe,
          );
          var removed = false;
          addTearDown(() {
            debugPrint = previousDebugPrint;
            if (!removed) board.onRemove();
            for (final attempt in probe.attempts) {
              final frame = attempt.acquired[MarkerDecoderStage.frame];
              if (frame is FrameInfo && !frame.image.debugDisposed) {
                frame.image.dispose();
              }
            }
          });

          var completed = false;
          Object? bakeError;
          var callsAtCompletion = <GameSprite>[];
          await runZonedGuarded(() async {
            try {
              if (startFromRender) {
                final recorder = PictureRecorder();
                board.render(Canvas(recorder));
                recorder.endRecording().dispose();
              } else {
                board.onMount();
              }
              await board.ensureMarkerShadows().timeout(
                const Duration(seconds: 2),
              );
              completed = true;
              callsAtCompletion = List.of(sheet.calls);
              for (var i = 0; i < 4; i++) {
                final recorder = PictureRecorder();
                board.render(Canvas(recorder));
                recorder.endRecording().dispose();
              }
              await Future<void>.delayed(const Duration(milliseconds: 20));
              await board.ensureMarkerShadows().timeout(
                const Duration(seconds: 2),
              );
            } catch (error) {
              bakeError = error;
              completed = false;
            }
          }, (error, stack) => uncaught.add(error));

          expect(completed, isTrue, reason: 'the bake must finish boundedly');
          expect(bakeError, isNull);
          expect(uncaught, isEmpty);
          expect(
            probe.attempts,
            hasLength(failureCase.bakeSprites.length),
            reason: 'the actual decoder must invoke the stage runner',
          );
          expect(
            callsAtCompletion,
            startFromRender
                ? [
                    GameSprite.spawnGate,
                    failureCase.bakeSprites.first,
                    GameSprite.baseReactor,
                    ...failureCase.bakeSprites.skip(1),
                  ]
                : failureCase.bakeSprites,
          );
          expect(sheet.calls.skip(callsAtCompletion.length), [
            for (var i = 0; i < 4; i++) ...[
              GameSprite.spawnGate,
              GameSprite.baseReactor,
            ],
          ], reason: 'rendering fallback sprites must not restart the bake');
          expect(diagnostics, [
            for (final (sprite, number) in failureCase.failures)
              'Marker shadow $sprite attempt $number failed: '
                  'Bad state: injected ${stage.name} decode failure',
          ]);

          for (var i = 0; i < probe.attempts.length; i++) {
            final attempt = probe.attempts[i];
            final failed = failureCase.failingAttempts.contains(i + 1);
            final expectedAcquired = MarkerDecoderStage.values
                .take(failed ? stage.index : MarkerDecoderStage.values.length)
                .toList();
            expect(attempt.failed, failed);
            expect(
              attempt.started,
              failed ? [...expectedAcquired, stage] : MarkerDecoderStage.values,
            );
            expect(attempt.acquired.keys, expectedAcquired);
            final expectedDisposal = expectedAcquired
                .where((value) => value != MarkerDecoderStage.frame)
                .toList()
                .reversed
                .toList();
            expect(attempt.disposed.map((entry) => entry.$1), expectedDisposal);
            for (final (disposedStage, resource) in attempt.disposed) {
              expect(
                identical(resource, attempt.acquired[disposedStage]),
                isTrue,
              );
            }
            final buffer = attempt.acquired[MarkerDecoderStage.buffer];
            if (buffer is ImmutableBuffer) {
              expect(buffer.debugDisposed, isTrue);
            }
            final frame = attempt.acquired[MarkerDecoderStage.frame];
            if (frame is FrameInfo) {
              expect(frame.image.debugDisposed, isFalse);
            }
          }
          board.onRemove();
          removed = true;
          for (final attempt in probe.attempts) {
            final frame = attempt.acquired[MarkerDecoderStage.frame];
            if (frame is FrameInfo) {
              expect(frame.image.debugDisposed, isTrue);
            }
          }
        });
      }
    }
  }

  testWidgets('decoder stage holds a real frame through mounted removal', (
    tester,
  ) async {
    final source = await tester.runAsync(
      () => Flame.images.load(GameSpriteSheet.fileName),
    );
    final sheet = _MarkerSheetProbe(GameSpriteSheet.fromImage(source!));
    final game = FlameGame();
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.runAsync(() async {
      final probe = _DecoderProbe(
        failureStage: MarkerDecoderStage.frame,
        failingAttempts: {},
        holdFirstFrame: true,
      );
      final board = BoardComponent(
        cellSize: 20,
        pathCells: BoardLayout.pathCells,
        spriteSheet: sheet,
        markerDecoderProbe: probe,
      );
      game.add(board);
      game.processLifecycleEvents();
      final bake = board.ensureMarkerShadows();
      try {
        expect(board.isMounted, isTrue);
        FrameInfo? frame;
        try {
          frame = await probe.frameReady.future.timeout(
            const Duration(seconds: 2),
          );
        } on TimeoutException {
          frame = null;
        }
        expect(frame, isNotNull, reason: 'the actual frame stage must run');
        expect(frame!.image.debugDisposed, isFalse);
        expect(sheet.calls, [GameSprite.spawnGate]);
        board.removeFromParent();
        game.processLifecycleEvents();
        expect(board.isRemoved, isTrue);
        expect(frame.image.debugDisposed, isFalse);
        probe.releaseFrame.complete();
        await bake.timeout(const Duration(seconds: 2));
        expect(frame.image.debugDisposed, isTrue);
        expect(sheet.calls, [GameSprite.spawnGate]);
        final attempt = probe.attempts.single;
        expect(attempt.disposed.map((entry) => entry.$1), [
          MarkerDecoderStage.codec,
          MarkerDecoderStage.descriptor,
          MarkerDecoderStage.buffer,
        ]);
        expect(
          (attempt.acquired[MarkerDecoderStage.buffer] as ImmutableBuffer)
              .debugDisposed,
          isTrue,
        );
      } finally {
        if (board.isMounted) {
          board.removeFromParent();
          game.processLifecycleEvents();
        }
        if (!probe.releaseFrame.isCompleted) probe.releaseFrame.complete();
        await bake.timeout(const Duration(seconds: 2));
        for (final attempt in probe.attempts) {
          final frame = attempt.acquired[MarkerDecoderStage.frame];
          if (frame is FrameInfo && !frame.image.debugDisposed) {
            frame.image.dispose();
          }
        }
      }
    });
  });

  for (final removeWhenDecoded in [false, true]) {
    testWidgets(
      removeWhenDecoded
          ? 'default decoder disposes a frame produced after mounted removal'
          : 'default decoder caches both frames until mounted removal',
      (tester) async {
        final source = await tester.runAsync(
          () => Flame.images.load(GameSpriteSheet.fileName),
        );
        final sheet = _MarkerSheetProbe(GameSpriteSheet.fromImage(source!));
        final game = FlameGame();
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();

        final created = <Image>[];
        final silhouettes = <Image>[];
        final decodedFrames = <Image>[];
        final previousOnCreate = Image.onCreate;
        var frameExpected = false;
        var removedWhileDecoding = false;
        late BoardComponent board;
        Image.onCreate = (image) {
          previousOnCreate?.call(image);
          created.add(image);
          if (!frameExpected) return;
          frameExpected = false;
          decodedFrames.add(image);
          if (removeWhenDecoded && !removedWhileDecoding) {
            board.removeFromParent();
            game.processLifecycleEvents();
            removedWhileDecoding = board.isRemoved;
          }
        };
        addTearDown(() {
          Image.onCreate = previousOnCreate;
          for (final image in created) {
            if (!image.debugDisposed) image.dispose();
          }
        });

        await tester.runAsync(() async {
          board = BoardComponent(
            cellSize: 20,
            pathCells: BoardLayout.pathCells,
            spriteSheet: sheet,
            markerReadback: (image) async {
              silhouettes.add(image);
              final data = await image.toByteData(
                format: ImageByteFormat.rawRgba,
              );
              frameExpected = true;
              return data;
            },
          );
          game.add(board);
          game.processLifecycleEvents();
          expect(board.isMounted, isTrue);
          await board.ensureMarkerShadows().timeout(const Duration(seconds: 2));

          expect(silhouettes.every((image) => image.debugDisposed), isTrue);
          if (removeWhenDecoded) {
            expect(removedWhileDecoding, isTrue);
            expect(sheet.calls, [GameSprite.spawnGate]);
            expect(decodedFrames, hasLength(1));
            expect(decodedFrames.single.debugDisposed, isTrue);
          } else {
            expect(sheet.calls, [GameSprite.spawnGate, GameSprite.baseReactor]);
            expect(decodedFrames, hasLength(2));
            expect(
              decodedFrames.every((image) => !image.debugDisposed),
              isTrue,
            );
            board.removeFromParent();
            game.processLifecycleEvents();
            expect(board.isRemoved, isTrue);
            expect(decodedFrames.every((image) => image.debugDisposed), isTrue);
          }
          expect(created.every((image) => image.debugDisposed), isTrue);
        });
      },
    );
  }

  for (final uploadPhase in [false, true]) {
    testWidgets(
      'injected pending ${uploadPhase ? 'upload' : 'readback'} is cancelled on removal',
      (tester) async {
        final source = await tester.runAsync(
          () => Flame.images.load(GameSpriteSheet.fileName),
        );
        final sheet = _MarkerSheetProbe(GameSpriteSheet.fromImage(source!));
        final game = FlameGame();
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        Image? silhouette;
        var readbacks = 0;
        var uploads = 0;
        final created = <Image>[];
        final previousOnCreate = Image.onCreate;
        Image.onCreate = (image) {
          previousOnCreate?.call(image);
          created.add(image);
        };
        addTearDown(() {
          Image.onCreate = previousOnCreate;
          for (final image in created) {
            if (!image.debugDisposed) image.dispose();
          }
        });
        await tester.runAsync(() async {
          final readbackGate = Completer<ByteData?>();
          final uploadGate = Completer<Image>();
          final uploadStarted = Completer<void>();
          final board = BoardComponent(
            cellSize: 20,
            pathCells: BoardLayout.pathCells,
            spriteSheet: sheet,
            markerReadback: (image) async {
              readbacks++;
              if (!uploadPhase && readbacks == 1) {
                silhouette = image;
                return readbackGate.future;
              }
              return ByteData(image.width * image.height * 4);
            },
            markerUpload: (pixels, width, height) async {
              uploads++;
              if (uploadPhase && uploads == 1) {
                uploadStarted.complete();
                return uploadGate.future;
              }
              return _uploadMarker(pixels, width, height);
            },
          );
          game.add(board);
          game.processLifecycleEvents();
          expect(board.isMounted, isTrue);
          final bake = board.ensureMarkerShadows();
          if (uploadPhase) await uploadStarted.future;
          expect(sheet.calls, [GameSprite.spawnGate]);
          board.removeFromParent();
          game.processLifecycleEvents();
          expect(board.isRemoved, isTrue);
          Image? lateImage;
          if (uploadPhase) {
            lateImage = await _rasterize(2, 2, (_) {});
            uploadGate.complete(lateImage);
          } else {
            readbackGate.complete(
              ByteData(silhouette!.width * silhouette!.height * 4),
            );
          }
          await bake;
          if (uploadPhase) {
            expect(lateImage!.debugDisposed, isTrue);
          } else {
            expect(silhouette!.debugDisposed, isTrue);
            expect(uploads, 0, reason: 'removal stops upload after readback');
          }
          expect(sheet.calls, [GameSprite.spawnGate]);
          expect(created.every((image) => image.debugDisposed), isTrue);
        });
      },
    );
  }

  for (final failure in ['null', 'throw']) {
    test('transient $failure readback is cleaned up and retried', () async {
      final sheet = _MarkerSheetProbe(
        GameSpriteSheet.fromImage(
          await Flame.images.load(GameSpriteSheet.fileName),
        ),
      );
      final silhouettes = <Image>[];
      final pictures = <Picture>[];
      final previousPictureCreate = Picture.onCreate;
      Picture.onCreate = (picture) {
        previousPictureCreate?.call(picture);
        pictures.add(picture);
      };
      var calls = 0;
      final board = BoardComponent(
        cellSize: 20,
        pathCells: BoardLayout.pathCells,
        spriteSheet: sheet,
        markerReadback: (image) async {
          silhouettes.add(image);
          calls++;
          if (calls == 1) {
            if (failure == 'throw') throw StateError('readback failed');
            return null;
          }
          return image.toByteData(format: ImageByteFormat.rawRgba);
        },
      );
      addTearDown(() {
        Picture.onCreate = previousPictureCreate;
        board.onRemove();
        for (final image in silhouettes) {
          if (!image.debugDisposed) image.dispose();
        }
        for (final picture in pictures) {
          if (!picture.debugDisposed) picture.dispose();
        }
      });
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await board.ensureMarkerShadows();
        } catch (_) {}
      }
      expect(silhouettes.first.debugDisposed, isTrue);
      expect(pictures, isNotEmpty);
      expect(pictures.every((picture) => picture.debugDisposed), isTrue);
      expect(calls, 3, reason: 'retry spawn and then bake the core');
      expect(sheet.calls, [
        GameSprite.spawnGate,
        GameSprite.spawnGate,
        GameSprite.baseReactor,
      ]);
    });
  }

  test('transient upload failure is retried for both marker shadows', () async {
    final sheet = _MarkerSheetProbe(
      GameSpriteSheet.fromImage(
        await Flame.images.load(GameSpriteSheet.fileName),
      ),
    );
    var uploads = 0;
    final board = BoardComponent(
      cellSize: 20,
      pathCells: BoardLayout.pathCells,
      spriteSheet: sheet,
      markerUpload: (pixels, width, height) {
        uploads++;
        if (uploads == 1) throw StateError('upload failed');
        return _uploadMarker(pixels, width, height);
      },
    );
    addTearDown(board.onRemove);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await board.ensureMarkerShadows();
      } catch (_) {}
    }
    expect(uploads, 3);
    expect(sheet.calls, [
      GameSprite.spawnGate,
      GameSprite.spawnGate,
      GameSprite.baseReactor,
    ]);
  });

  for (final failure in ['readback throw', 'readback null', 'upload throw']) {
    for (final startFromRender in [false, true]) {
      test('persistent $failure has bounded fallback from '
          '${startFromRender ? 'render' : 'onMount'}', () async {
        final source = await Flame.images.load(GameSpriteSheet.fileName);
        var attempts = 0;
        final silhouettes = <Image>[];
        final diagnostics = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) diagnostics.add(message);
        };
        final board = BoardComponent(
          cellSize: 20,
          pathCells: BoardLayout.pathCells,
          spriteSheet: GameSpriteSheet.fromImage(source),
          markerReadback: (image) async {
            silhouettes.add(image);
            if (failure.startsWith('readback')) {
              attempts++;
              if (failure == 'readback null') return null;
              throw StateError('persistent readback failure');
            }
            return image.toByteData(format: ImageByteFormat.rawRgba);
          },
          markerUpload: (pixels, width, height) {
            attempts++;
            throw StateError('persistent upload failure');
          },
        );
        addTearDown(() {
          debugPrint = previousDebugPrint;
          board.onRemove();
          for (final image in silhouettes) {
            if (!image.debugDisposed) image.dispose();
          }
        });
        final uncaught = <Object>[];
        await runZonedGuarded(() async {
          if (!startFromRender) board.onMount();
          for (var frame = 0; frame < 10; frame++) {
            final recorder = PictureRecorder();
            board.render(Canvas(recorder));
            recorder.endRecording().dispose();
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        }, (error, stack) => uncaught.add(error));
        expect(uncaught, isEmpty);
        expect(
          attempts,
          4,
          reason: 'each marker gets two attempts, not per-frame retries',
        );
        expect(diagnostics, hasLength(4));
        expect(
          diagnostics.every(
            (line) => line.contains(
              failure == 'readback null'
                  ? 'readback returned null'
                  : 'persistent ${failure.split(' ').first} failure',
            ),
          ),
          isTrue,
        );
        expect(silhouettes.every((image) => image.debugDisposed), isTrue);
      });
    }
  }

  test(
    'a failed spawn shadow does not prevent a successful core shadow',
    () async {
      final sheet = _MarkerSheetProbe(
        GameSpriteSheet.fromImage(
          await Flame.images.load(GameSpriteSheet.fileName),
        ),
      );
      var readbacks = 0;
      final uploaded = <Image>[];
      final board = BoardComponent(
        cellSize: 20,
        pathCells: BoardLayout.pathCells,
        spriteSheet: sheet,
        markerReadback: (image) async {
          readbacks++;
          if (readbacks <= 2) throw StateError('spawn readback failed');
          return image.toByteData(format: ImageByteFormat.rawRgba);
        },
        markerUpload: (pixels, width, height) async {
          final image = await _uploadMarker(pixels, width, height);
          uploaded.add(image);
          return image;
        },
      );
      addTearDown(() {
        board.onRemove();
        for (final image in uploaded) {
          if (!image.debugDisposed) image.dispose();
        }
      });
      await board.ensureMarkerShadows();
      expect(sheet.calls, [
        GameSprite.spawnGate,
        GameSprite.spawnGate,
        GameSprite.baseReactor,
      ]);
      expect(uploaded, hasLength(1));
      expect(uploaded.single.debugDisposed, isFalse);
    },
  );

  for (final checkDisposal in [false, true]) {
    testWidgets(
      checkDisposal
          ? 'removing a board during a marker bake disposes every produced image'
          : 'removing a board during a marker bake stops later markers',
      (tester) async {
        final image = await tester.runAsync(
          () => Flame.images.load(GameSpriteSheet.fileName),
        );
        final sheet = _MarkerSheetProbe(GameSpriteSheet.fromImage(image!));
        final game = FlameGame();
        await tester.pumpWidget(GameWidget(game: game));
        await tester.pump();
        expect(game.isMounted, isTrue);

        final created = <Image>[];
        final previousOnCreate = Image.onCreate;
        Image.onCreate = (image) {
          previousOnCreate?.call(image);
          created.add(image);
        };
        addTearDown(() {
          Image.onCreate = previousOnCreate;
          for (final image in created) {
            if (!image.debugDisposed) image.dispose();
          }
        });

        await tester.runAsync(() async {
          final board = BoardComponent(
            cellSize: 20,
            pathCells: BoardLayout.pathCells,
            spriteSheet: sheet,
          );
          game.add(board);
          game.processLifecycleEvents();
          expect(board.isMounted, isTrue);
          final bake = board.ensureMarkerShadows();
          expect(sheet.calls, [GameSprite.spawnGate]);
          expect(created, isNotEmpty);
          board.removeFromParent();
          game.processLifecycleEvents();
          expect(board.isRemoved, isTrue);
          await bake;
          if (checkDisposal) {
            expect(
              created.every((image) => image.debugDisposed),
              isTrue,
              reason: 'no image produced by a removed board may remain owned',
            );
          } else {
            expect(
              sheet.calls,
              [GameSprite.spawnGate],
              reason: 'removal must prevent the core marker bake from starting',
            );
          }
        });
      },
    );
  }

  for (final failedSprite in [GameSprite.spawnGate, GameSprite.baseReactor]) {
    test(
      'a transient $failedSprite bake error does not poison subsequent attempts',
      () async {
        final sheet = _MarkerSheetProbe(
          GameSpriteSheet.fromImage(
            await Flame.images.load(GameSpriteSheet.fileName),
          ),
          failOnce: true,
          failSprite: failedSprite,
        );
        final board = BoardComponent(
          cellSize: 20,
          pathCells: BoardLayout.pathCells,
          spriteSheet: sheet,
        );
        addTearDown(board.onRemove);
        final errors = <Object>[];
        final completed = <bool>[];
        for (var attempt = 0; attempt < 2; attempt++) {
          try {
            await board.ensureMarkerShadows();
            completed.add(true);
          } catch (error) {
            errors.add(error);
            completed.add(false);
          }
        }
        expect(
          sheet.calls.where((sprite) => sprite == failedSprite).length,
          2,
          reason: 'a transient failure must leave a way to retry the marker',
        );
        expect(sheet.calls, contains(GameSprite.baseReactor));
        expect(errors.length, lessThanOrEqualTo(1));
        expect(completed.last, isTrue);
      },
    );
  }

  for (final startFromRender in [false, true]) {
    test('fire-and-forget marker bake errors stay inside the board from '
        '${startFromRender ? 'render' : 'onMount'}', () async {
      final sheet = _MarkerSheetProbe(
        GameSpriteSheet.fromImage(
          await Flame.images.load(GameSpriteSheet.fileName),
        ),
        failOnce: true,
        failLookup: startFromRender ? 2 : 1,
      );
      final board = BoardComponent(
        cellSize: 20,
        pathCells: BoardLayout.pathCells,
        spriteSheet: sheet,
      );
      addTearDown(board.onRemove);
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        if (startFromRender) {
          final recorder = PictureRecorder();
          board.render(Canvas(recorder));
          recorder.endRecording().dispose();
        } else {
          board.onMount();
        }
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }, (error, stack) => uncaught.add(error));
      expect(sheet.failOnce, isFalse, reason: 'the injected error was reached');
      expect(uncaught, isEmpty);
    });
  }

  test(
    'persistent render sprite lookup failure falls back without retrying every frame',
    () async {
      final sheet = _MarkerSheetProbe(
        GameSpriteSheet.fromImage(
          await Flame.images.load(GameSpriteSheet.fileName),
        ),
        alwaysFail: true,
      );
      final board = BoardComponent(
        cellSize: 20,
        pathCells: BoardLayout.pathCells,
        spriteSheet: sheet,
      );
      addTearDown(board.onRemove);
      final uncaught = <Object>[];
      await runZonedGuarded(() async {
        for (var frame = 0; frame < 10; frame++) {
          final recorder = PictureRecorder();
          try {
            board.render(Canvas(recorder));
          } catch (error) {
            uncaught.add(error);
          }
          recorder.endRecording().dispose();
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }, (error, stack) => uncaught.add(error));
      expect(uncaught, isEmpty);
      expect(
        sheet.calls.where((sprite) => sprite == GameSprite.spawnGate).length,
        lessThanOrEqualTo(4),
      );
    },
  );

  group('BoardComponent.dashed', () {
    test('cuts a line into dash/gap segments', () {
      final result = BoardComponent.dashed(_line(100), dash: 10, gap: 10);

      // 100 units at a 20-unit period: dashes at 0, 20, 40, 60, 80.
      expect(result.computeMetrics().length, 5);
      expect(_totalLength(result), closeTo(50, 0.01));
    });

    test('clips the trailing dash to the end of the line', () {
      final result = BoardComponent.dashed(_line(25), dash: 10, gap: 10);

      // Dashes at 0-10 and 20-25: the last one is cut short, not extended.
      expect(result.computeMetrics().length, 2);
      expect(_totalLength(result), closeTo(15, 0.01));
    });

    test('returns the undashed line for a non-positive dash', () {
      // A zero dash would advance the walk by nothing and never terminate.
      final result = BoardComponent.dashed(_line(100), dash: 0, gap: 0);

      expect(_totalLength(result), closeTo(100, 0.01));
    });
  });

  group('BoardComponent lane rendering', () {
    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    test('renders a multi-cell path', () {
      final board = BoardComponent(
        cellSize: 32,
        pathCells: const [
          GridPosition(0, 0),
          GridPosition(1, 0),
          GridPosition(1, 1),
        ],
      );

      expect(() => renderTo(board), returnsNormally);
    });

    test('renders a single-cell path, which has no lane to draw', () {
      final board = BoardComponent(
        cellSize: 32,
        pathCells: const [GridPosition(0, 0)],
      );

      expect(() => renderTo(board), returnsNormally);
    });

    test('renders a degenerate board before the first resize', () {
      final board = BoardComponent(
        cellSize: 0,
        pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
      );

      expect(() => renderTo(board), returnsNormally);
    });
  });

  group('BoardComponent range ring', () {
    BoardComponent previewBoard() =>
        BoardComponent(
            cellSize: 32,
            pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
          )
          ..previewActive = true
          ..previewCandidate = const GridPosition(4, 4)
          ..previewAllowed = true
          ..previewRange = 90;

    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    test('is dashed, not a solid circle', () {
      const radius = 90.0;
      final board = previewBoard();

      final ring = board.rangeRingPath(Offset.zero, radius);

      // Equal dash and gap, so about half the circumference survives. The
      // slack absorbs what computeMetrics loses walking a polyline
      // approximation of the oval.
      const circumference = 2 * math.pi * radius;
      expect(
        _totalLength(ring),
        closeTo(circumference / 2, 0.1 * circumference / 2),
      );
      expect(ring.computeMetrics().length, greaterThan(20));
    });

    test('is the artboard\'s naniteGreen, at full-strength 2px', () {
      final board = previewBoard();

      renderTo(board);

      // The ring belongs to the allowed state, so it matches the buildable
      // cell's green rather than the dragged tower's own colour.
      expect(
        board.rangeRingPaint.color.toARGB32(),
        const Color(0xB37BE495).toARGB32(),
      );
      expect(board.rangeRingPaint.strokeWidth, 2);
    });

    test('renders without throwing over a blocked candidate', () {
      final board = previewBoard()..previewAllowed = false;

      expect(() => renderTo(board), returnsNormally);
    });
  });

  group('BoardComponent placement grid', () {
    void renderTo(BoardComponent board) {
      final recorder = PictureRecorder();
      board.render(Canvas(recorder));
      recorder.endRecording();
    }

    BoardComponent board() => BoardComponent(
      cellSize: 32,
      pathCells: const [GridPosition(0, 0), GridPosition(1, 0)],
    );

    test('is hidden at rest and shown while a placement is armed', () {
      // The artboard draws cell lines only while armed; at rest the board is
      // its own art.
      expect(board().showsPlacementGrid, isFalse);

      final armed = board()
        ..previewActive = true
        ..previewCandidate = const GridPosition(4, 4);

      expect(armed.showsPlacementGrid, isTrue);
      expect(() => renderTo(armed), returnsNormally);
    });

    test('is naniteGreen at the artboard alpha, not grey chrome', () {
      expect(
        board().gridPaint.color.toARGB32(),
        const Color(0x2E7BE495).toARGB32(),
      );
    });

    test('a selected cell alone does not arm the grid', () {
      // Selecting a cell shows its highlight; only a placement shows the grid.
      final selected = board()..selectedCell = const GridPosition(2, 2);

      expect(selected.showsSelectionHighlight, isTrue);
      expect(selected.showsPlacementGrid, isFalse);
    });
  });

  group('BoardComponent board.js readability (HPA-699)', () {
    const cell = 40.0;

    BoardComponent board() =>
        BoardComponent(cellSize: cell, pathCells: BoardLayout.pathCells);

    Future<Image> renderBoard() => _rasterize(
      (BoardLayout.columns * cell).ceil(),
      (BoardLayout.rows * cell).ceil(),
      board().render,
    );

    test('the lane corridor paints a dark channel inside the rim', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.82 * cell).round(),
      );
      expect(pixel[0], lessThan(0x30));
      expect(pixel[1], lessThan(0x45));
      expect(pixel[2], lessThan(0x50));
    });

    test('the lane keeps a steel-cyan rim around the channel', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.88 * cell).round(),
      );
      expect(pixel[0], lessThan(0x45));
      expect(pixel[2], greaterThan(pixel[0]));
    });

    test('the centre line carries chevrons, not a cyan stripe', () async {
      final image = await renderBoard();
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final y = (1.5 * cell).round();
      var cyanish = 0;
      var samples = 0;
      for (var x = (0.6 * cell).round(); x < (3.4 * cell).round(); x++) {
        final index = (y * image.width + x) * 4;
        final r = data!.getUint8(index);
        final g = data.getUint8(index + 1);
        final b = data.getUint8(index + 2);
        final a = data.getUint8(index + 3);
        if (a > 0) {
          samples += 1;
          if (g > 150 && b > 150 && r < 100) cyanish += 1;
        }
      }
      expect(samples, greaterThan(0));
      expect(
        cyanish / samples,
        lessThan(0.4),
        reason:
            'flow chevrons are sparse glyphs, so most of the centre line '
            'stays the dark channel',
      );
    });

    test('a faint always-on grid borders every cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(image, cell.round(), (8.5 * cell).round());
      expect(pixel[3], greaterThan(0));
      expect(pixel[2], greaterThanOrEqualTo(pixel[0]));
    });

    test('the spawn marker reads larger than its cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (1.0 * cell).round(),
      );
      expect(pixel[3], greaterThan(0));
    });

    test('the core marker reads larger than its cell', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (6.95 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(pixel[3], greaterThan(0));
    });

    test('cell geometry stays aligned with BoardLayout after the repaint', () {
      final component = board();
      for (final position in BoardLayout.pathCells) {
        expect(
          component.cellCenter(position),
          BoardLayout.cellCenter(
            position,
            cellSize: cell,
            boardOrigin: Offset.zero,
          ),
        );
        expect(
          component.cellRect(position).contains(component.cellCenter(position)),
          isTrue,
        );
      }
    });

    test('the lane rim is the kit steel-cyan at the kit band', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.88 * cell).round(),
      );
      expect(
        pixel[0],
        closeTo(0x2C, 4),
        reason: 'board.js strokes the rim #2C6F86, not a fabricated hue',
      );
      expect(pixel[1], closeTo(0x6F, 4));
      expect(pixel[2], closeTo(0x86, 4));
    });

    test('the lane channel is the kit dark blue at the kit band', () async {
      final image = await renderBoard();
      final pixel = await _rgbaAt(
        image,
        (2.5 * cell).round(),
        (1.80 * cell).round(),
      );
      expect(pixel[0], closeTo(0x08, 3));
      expect(pixel[1], closeTo(0x12, 3));
      expect(pixel[2], closeTo(0x1B, 3));
    });

    test(
      'the lane centre carries the kit core line between chevrons',
      () async {
        final image = await renderBoard();
        final data = await image.toByteData(format: ImageByteFormat.rawRgba);
        final y = (1.5 * cell).round();
        var matching = 0;
        var samples = 0;
        for (var x = (1.0 * cell).round(); x < (3.0 * cell).round(); x++) {
          final index = (y * image.width + x) * 4;
          final r = data!.getUint8(index);
          final g = data.getUint8(index + 1);
          final b = data.getUint8(index + 2);
          final a = data.getUint8(index + 3);
          if (a == 0 || (g > 150 && b > 150 && r < 100)) continue;
          samples += 1;
          if ((r - 0x0E).abs() <= 4 &&
              (g - 0x22).abs() <= 4 &&
              (b - 0x30).abs() <= 4) {
            matching += 1;
          }
        }
        expect(samples, greaterThan(10));
        expect(
          matching / samples,
          greaterThan(0.8),
          reason:
              'board.js runs a #0E2230 lane core at C*.5 under the chevrons; '
              'the bare centreline must read that value, not the channel',
        );
      },
    );

    test(
      'the field grid is the kit cyan at seven percent, not opaque',
      () async {
        final image = await renderBoard();
        final pixel = await _rgbaAt(image, cell.round(), (8.5 * cell).round());
        expect(
          pixel[3],
          allOf(greaterThan(4), lessThan(64)),
          reason:
              'rgba(70,230,255,.07) composites to a faint line; an opaque '
              'grid tile is off-kit',
        );
        expect(pixel[2], greaterThanOrEqualTo(pixel[0]));
        expect(pixel[1], greaterThan(pixel[0]));
      },
    );

    test('flow chevrons land one per cell along a straight run', () async {
      final image = await renderBoard();
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      final y = (1.5 * cell).round();
      final runs = <int>[];
      var inRun = false;
      for (var x = (0.6 * cell).round(); x < (3.4 * cell).round(); x++) {
        final index = (y * image.width + x) * 4;
        final r = data!.getUint8(index);
        final g = data.getUint8(index + 1);
        final b = data.getUint8(index + 2);
        final a = data.getUint8(index + 3);
        final cyanish = a > 0 && g > 150 && b > 150 && r < 100;
        if (cyanish && !inRun) {
          runs.add(x);
          inRun = true;
        } else if (!cyanish) {
          inRun = false;
        }
      }
      expect(
        runs.length,
        3,
        reason:
            'board.js places one chevron per cell of segment length; '
            '${runs.length} clusters on a 3-cell run is off-kit',
      );
      for (var i = 1; i < runs.length; i++) {
        expect(
          runs[i] - runs[i - 1],
          closeTo(cell.round(), (0.3 * cell).round()),
          reason: 'chevron pitch must be ~one cell, not a fabricated rhythm',
        );
      }
    });

    test('the spawn marker fills the kit 1.35C disc and no more', () async {
      final image = await renderBoard();
      final covered = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (0.84 * cell).round(),
      );
      expect(
        covered[3],
        greaterThan(0),
        reason:
            'the kit spawn rift spans C*1.35; 0.66C from centre must still '
            'be inside the disc',
      );
      final outside = await _rgbaAt(
        image,
        (0.5 * cell).round(),
        (0.78 * cell).round(),
      );
      expect(
        outside[3],
        lessThan(20),
        reason:
            '0.72C from centre is outside a 1.35C marker: only the kit '
            'halo\'s faint Gaussian tail may reach it now — an opaque disc '
            'covering the probe still means the spawn inherited the '
            'core\'s larger size',
      );
    });

    test('the core marker fills the kit 1.45C disc and no more', () async {
      final image = await renderBoard();
      final covered = await _rgbaAt(
        image,
        (6.80 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(
        covered[3],
        greaterThan(0),
        reason:
            'the kit core spans C*1.45; 0.70C from centre must still be '
            'inside the disc',
      );
      final outside = await _rgbaAt(
        image,
        (6.69 * cell).round(),
        (10.5 * cell).round(),
      );
      expect(
        outside[3],
        lessThan(20),
        reason:
            '0.81C from centre is outside a 1.45C marker: only the kit '
            'halo\'s faint Gaussian tail may reach it now — an opaque disc '
            'covering the probe still means the core grew past its kit '
            'size',
      );
    });
  });

  group('BoardComponent board.js acceptance — gaussian lane halo and sprite '
      'marker drop-shadows (fix round 2)', () {
    const cell = 46.75;

    Future<Image> renderKitBoard({
      GameSpriteSheet? spriteSheet,
      double pad = 0,
    }) async {
      final board = BoardComponent(
        cellSize: cell,
        pathCells: BoardLayout.pathCells,
        spriteSheet: spriteSheet,
      );
      await board.ensureMarkerShadows();
      return _rasterize(
        (BoardLayout.columns * cell + pad * 2).ceil(),
        (BoardLayout.rows * cell + pad * 2).ceil(),
        (canvas) {
          canvas.translate(pad, pad);
          board.render(canvas);
        },
      );
    }

    test('the lane halo is a gaussian falloff past the .92C band, not four '
        'hard-edged strokes that end at 0.65C', () async {
      final image = await renderKitBoard();
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      int alphaAt(int x, int y) =>
          data!.getUint8((y * image.width + x) * 4 + 3);

      final x = (1.25 * cell).round();

      var tail = 0;
      for (var y = (0.62 * cell).ceil(); y <= (0.79 * cell).floor(); y++) {
        tail += alphaAt(x, y);
      }
      expect(
        tail,
        greaterThan(0),
        reason:
            'the kit halo is a σ=6 gaussian of the .92C stroke — a '
            'faint cyan tail must still emit between 0.66C and 0.85C '
            'from the centreline; four stair-stepped strokes end '
            'hard at 0.65C',
      );

      final near = alphaAt(x, (0.90 * cell).round());
      final far = alphaAt(x, (0.66 * cell).round());
      expect(
        near,
        greaterThanOrEqualTo(5),
        reason:
            'the σ6 halo emits a few percent at 0.60C from the '
            'centreline; a hard band emits nothing past its last stroke',
      );
      expect(
        near,
        greaterThan(far),
        reason:
            'the Gaussian falls off with distance (≈8/255 at 0.60C → 0 at '
            '0.84C); any uniform-width stroke would read flat across both',
      );
    });

    test('the spawn sprite casts the kit cyan drop-shadow beyond its art '
        'rect', () async {
      final sheet = GameSpriteSheet.fromImage(
        await Flame.images.load(GameSpriteSheet.fileName),
      );
      final image = await renderKitBoard(spriteSheet: sheet);
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      int alphaAt(int x, int y) =>
          data!.getUint8((y * image.width + x) * 4 + 3);
      int redAt(int x, int y) => data!.getUint8((y * image.width + x) * 4);
      int blueAt(int x, int y) => data!.getUint8((y * image.width + x) * 4 + 2);

      final x = (0.5 * cell).round();
      var strongCyan = 0;
      for (var y = (0.62 * cell).ceil(); y <= (0.81 * cell).floor(); y++) {
        if (alphaAt(x, y) >= 8 && blueAt(x, y) > redAt(x, y)) {
          strongCyan += 1;
        }
      }
      expect(
        strongCyan,
        greaterThan(0),
        reason:
            'drop-shadow(0 0 12px rgba(70,230,255,.9)) must bloom the '
            'spawn sprite cyan past its rect; the sprite is painted '
            'bare today — no shadow rows found',
      );
    });

    test('the core sprite casts the kit amber drop-shadow beyond its art '
        'rect', () async {
      final sheet = GameSpriteSheet.fromImage(
        await Flame.images.load(GameSpriteSheet.fileName),
      );
      final image = await renderKitBoard(spriteSheet: sheet);

      const centre = Offset(7.5 * cell, 10.5 * cell);
      const dirs = [Offset(-1, 0), Offset(-0.707, 0.707), Offset(0, 1)];
      var amberGlow = 0;
      for (final dir in dirs) {
        for (var r = 0.74; r <= 0.90; r += 0.04) {
          final x = (centre.dx + dir.dx * r * cell).round();
          final y = (centre.dy + dir.dy * r * cell).round();
          if (x < 0 || y < 0 || x >= image.width || y >= image.height) {
            continue;
          }
          final pixel = await _rgbaAt(image, x, y);
          if (pixel[3] >= 4 && pixel[0] > pixel[2]) {
            amberGlow += 1;
          }
        }
      }
      expect(
        amberGlow,
        greaterThan(0),
        reason:
            'drop-shadow(0 0 16px rgba(255,200,87,.95)) must bloom '
            'the core sprite amber past its rect; nothing renders '
            'outside the sprite clip today',
      );
    });

    test('the spawn shadow is the sprite alpha silhouette, not its padded '
        'cell disc', () async {
      final sheet = GameSpriteSheet.fromImage(
        await Flame.images.load(GameSpriteSheet.fileName),
      );
      final image = await renderKitBoard(spriteSheet: sheet);
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      int alphaAt(int x, int y) =>
          data!.getUint8((y * image.width + x) * 4 + 3);
      int redAt(int x, int y) => data!.getUint8((y * image.width + x) * 4);
      int blueAt(int x, int y) => data!.getUint8((y * image.width + x) * 4 + 2);
      int cyanAt(int x, int y) =>
          alphaAt(x, y) >= 4 && blueAt(x, y) > redAt(x, y) ? alphaAt(x, y) : 0;

      int bestCyanAt(double y) {
        var best = 0;
        for (var dx = -10; dx <= 10; dx += 2) {
          final v = cyanAt((0.5 * cell).round() + dx, y.round());
          if (v > best) best = v;
        }
        return best;
      }

      final rectTop = 1.5 * cell - 0.675 * cell;
      final rectBottom = 1.5 * cell + 0.675 * cell;
      final topCyan = bestCyanAt(rectTop - 10);
      final bottomCyan = bestCyanAt(rectBottom + 10);
      expect(
        topCyan,
        greaterThanOrEqualTo(20),
        reason:
            'the spawn alpha nearly reaches the cell top, so its '
            'drop-shadow(0 0 12px rgba(70,230,255,.9)) must bloom '
            'cyan visibly just above the marker rect',
      );
      expect(
        bottomCyan,
        lessThanOrEqualTo(25),
        reason:
            'the spawn alpha ends 26% above the cell bottom edge — '
            '~16px plus 10px off-rect is ~2.2 sigma from the real '
            'silhouette, so almost no cyan may reach the symmetric '
            'bottom probe; a blurred disc lights it as strongly as '
            'the top probe',
      );
      expect(
        topCyan,
        greaterThanOrEqualTo(bottomCyan * 2),
        reason:
            'the sprite silhouette is vertically asymmetric inside its '
            'padded cell; only a disc makes the shadow symmetric',
      );
    });

    test('the core shadow is the sprite alpha silhouette, not its padded '
        'cell disc', () async {
      final sheet = GameSpriteSheet.fromImage(
        await Flame.images.load(GameSpriteSheet.fileName),
      );
      const pad = 44.0;
      final image = await renderKitBoard(spriteSheet: sheet, pad: pad);
      final data = await image.toByteData(format: ImageByteFormat.rawRgba);
      int alphaAt(int x, int y) =>
          data!.getUint8((y * image.width + x) * 4 + 3);
      int redAt(int x, int y) => data!.getUint8((y * image.width + x) * 4);
      int blueAt(int x, int y) => data!.getUint8((y * image.width + x) * 4 + 2);
      int amberAt(int x, int y) =>
          alphaAt(x, y) >= 4 && redAt(x, y) > blueAt(x, y) ? alphaAt(x, y) : 0;

      int bestAmberRight(int dx) {
        var best = 0;
        for (
          var y = (10.15 * cell + pad).round();
          y <= (10.9 * cell + pad).round();
          y += 2
        ) {
          final v = amberAt((8.225 * cell + pad).round() + dx, y);
          if (v > best) best = v;
        }
        return best;
      }

      int bestAmberBelow(int dy) {
        var best = 0;
        for (
          var x = (6.9 * cell + pad).round();
          x <= (8.1 * cell + pad).round();
          x += 2
        ) {
          final v = amberAt(x, (10.5 * cell + 0.725 * cell + pad).round() + dy);
          if (v > best) best = v;
        }
        return best;
      }

      final rightAmber = bestAmberRight(4);
      final bottomAmber = bestAmberBelow(10);
      expect(
        rightAmber,
        greaterThanOrEqualTo(20),
        reason:
            'the core alpha ends ~9px inside the rect right edge, so its '
            'drop-shadow(0 0 16px rgba(255,200,87,.95)) must bloom amber '
            'visibly just off that edge — nothing outside the sprite '
            'clip at all means the shadow is not the sprite silhouette',
      );
      expect(
        bottomAmber,
        lessThanOrEqualTo(15),
        reason:
            'the core alpha ends ~18px inside the rect bottom — plus '
            '10px off-rect is ~1.75 sigma from the real silhouette, so '
            'the tail must already be faint here; a blurred rect-edge '
            'shape lights it as strongly as the right probe',
      );
      expect(
        rightAmber,
        greaterThanOrEqualTo(bottomAmber * 2),
        reason:
            'the sprite silhouette is asymmetric inside its padded cell; '
            'only a rect-fitting shape makes the shadow symmetric',
      );
    });
  });
}
