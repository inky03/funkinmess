package funkin.states;

import flixel.system.debug.stats.Stats;
import openfl.events.KeyboardEvent;
import flixel.input.keyboard.FlxKey;
import flixel.FlxState;

import funkin.backend.scripting.HScript;
import funkin.backend.play.ScoreHandler;
import funkin.backend.play.NoteEvent;
import funkin.backend.play.Scoring;
import funkin.backend.play.Chart;
import funkin.objects.play.*;
import funkin.objects.*;

using StringTools;

class PlayState extends funkin.backend.states.FunkinState {
	public var player1:Character;
	public var player2:Character;
	public var player3:Character;
	
	public var stage:Stage;
	public var curStage:String;
	
	public var healthBar:Bar;
	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var scoreTxt:FlxText;
	public var debugTxt:FlxText;
	public var opponentStrumline:Strumline;
	public var playerStrumline:Strumline;
	public var uiGroup:FlxSpriteGroup;
	public var ratingGroup:FlxTypedSpriteGroup<FunkinSprite>;
	
	public var scoring:ScoreHandler = new ScoreHandler(EMI);
	public var singAnimations:Array<String> = ['LEFT', 'DOWN', 'UP', 'RIGHT'];
	public var keybinds:Array<Array<FlxKey>> = [];
	public var heldKeys:Array<FlxKey> = [];
	public var inputDisabled:Bool = false;
	public var playCountdown:Bool = true;
	
	public var camHUD:FunkinCamera;
	public var camGame:FunkinCamera;
	public var camOther:FunkinCamera;
	public var camFocusTarget:FlxObject;
	
	public var camZoomRate:Int = -1; // 0: no bop - <0: every measure (always)
	public var camZoomIntensity:Float = 1;
	public var hudZoomIntensity:Float = 2;
	
	public static var chart:Chart = null;
	public var events:Array<ChartEvent> = [];
	public var notes:Array<Note> = [];
	public var songName:String;
	
	public var maxHealth(default, set):Float = 1;
	public var health(default, set):Float = .5;
	public var score:Float = 0;
	public var misses:Int = 0;
	public var combo(default, set):Int = 0;
	public var accuracyMod:Float = 0;
	public var accuracyDiv:Float = 0;
	public var totalNotes:Int = 0;
	public var totalHits:Int = 0;
	public var percent:Float = 0;
	public var dead:Bool = false;
	public var gameOver:GameOverSubState;
	
	public var music:FunkinSoundGroup;
	public var hitsound:FunkinSound;
	
	public var godmode:Bool;
	public var downscroll:Bool;
	public var middlescroll:Bool;
	
	public function new() {
		chart ??= new Chart('');
		chart.instLoaded = false;
		super();
	}
	
	override public function create() {
		super.create();
		Main.watermark.visible = false;
		godmode = false; // practice mode?
		downscroll = Options.data.downscroll;
		middlescroll = Options.data.middlescroll;
		
		conductorInUse = new Conductor();
		conductorInUse.metronome.tempoChanges = chart.tempoChanges;
		
		hitsound = FunkinSound.load(Paths.sound('gameplay/hitsounds/hitsound'), .7);
		music = new FunkinSoundGroup();
		songName = chart.name;
		
		hscripts.loadFromFolder('scripts/global');
		hscripts.loadFromFolder('scripts/songs/${chart.path}');
		
		stepHit.add(stepHitEvent);
		beatHit.add(beatHitEvent);
		barHit.add(barHitEvent);
		
		@:privateAccess FlxG.cameras.defaults.resize(0);
		camOther = new FunkinCamera();
		camGame = new FunkinCamera();
		camHUD = new FunkinCamera();
		camHUD.bgColor.alpha = 0;
		camGame.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;
		FlxG.cameras.add(camGame, true);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		
		camFocusTarget = new FlxObject(0, FlxG.height * .5);
		camGame.follow(camFocusTarget, LOCKON, 3);
		add(camFocusTarget);
		
		camGame.zoomFollowLerp = camHUD.zoomFollowLerp = 3;
		
		stage = new Stage(chart);
		stage.setup(chart.stage);
		camGame.zoomTarget = stage.zoom;
		camHUD.zoomTarget = 1;
		add(stage);
		
		player1 = stage.getCharacter('bf');
		player2 = stage.getCharacter('dad');
		player3 = stage.getCharacter('gf');
		
		focusOnCharacter(player3 ?? player1);
		camGame.snapToTarget();
		
		var path:String = 'data/songs/${chart.path}/';
		chart.loadMusic(path, false);
		if (chart.instLoaded) {
			music.add(chart.inst);
			music.syncBase = chart.inst;
			music.onSoundFinished.add((snd:FunkinSound) -> {
				if (snd == music.syncBase)
					finishSong();
			});
			conductorInUse.syncTracker = chart.inst;
		} else {
			Log.warning('chart instrumental not found...');
			Log.minor('verify path:');
			Log.minor('- $path${Util.pathSuffix('Inst', chart.audioSuffix)}.ogg');
		}
		loadVocals(chart.path, chart.audioSuffix);
		
		uiGroup = new FlxSpriteGroup();
		uiGroup.camera = camHUD;
		add(uiGroup);
		
		var scrollDir:Float = (Options.data.downscroll ? 270 : 90);
		var strumlineBound:Float = (FlxG.width - 300) * .5;
		var strumlineY:Float = 50;
		
		opponentStrumline = new Strumline(4, scrollDir, chart.scrollSpeed);
		opponentStrumline.fitToSize(strumlineBound, opponentStrumline.height * .7);
		opponentStrumline.setPosition(50, strumlineY);
		opponentStrumline.zIndex = 40;
		opponentStrumline.cpu = true;
		opponentStrumline.allowInput = false;
		
		playerStrumline = new Strumline(4, scrollDir, chart.scrollSpeed * 1.08);
		playerStrumline.fitToSize(strumlineBound, playerStrumline.height * .7);
		playerStrumline.setPosition(FlxG.width - playerStrumline.width - 50 - 75, strumlineY);
		playerStrumline.zIndex = 50;
		
		if (middlescroll) {
			playerStrumline.screenCenter(X);
			opponentStrumline.fitToSize(playerStrumline.leftBound - 50 - opponentStrumline.leftBound, 0, Y);
		}
		
		opponentStrumline.noteEvent.add(opponentNoteEvent);
		playerStrumline.noteEvent.add(playerNoteEvent);
		opponentStrumline.visible = false;
		playerStrumline.visible = false;
		
		keybinds = Options.data.keybinds['4k'];
		playerStrumline.assignKeybinds(keybinds);
		
		var noteKinds:Array<String> = [];
		for (note in chart.generateNotes()) {
			var noteKind:String = note.noteKind;
			if (noteKind.trim() != '' && !noteKinds.contains(noteKind)) {
				noteKinds.push(noteKind);
				hscripts.loadFromPaths('scripts/notekinds/$noteKind.hx');
			}

			var strumline:Strumline = (note.player ? playerStrumline : opponentStrumline);
			strumline.queueNote(note);
			notes.push(note);
		}
		
		ratingGroup = new FlxTypedSpriteGroup<FunkinSprite>();
		ratingGroup.setPosition(player3?.getMidpoint()?.x ?? FlxG.width * .5, player3?.getMidpoint()?.y ?? FlxG.height * .5);
		ratingGroup.zIndex = (player3?.zIndex ?? 0) + 10;
		if (stage != null) stage.insertZIndex(ratingGroup);
		else add(ratingGroup);
		
		healthBar = new Bar(0, FlxG.height - 50, (_) -> health, 'healthBar');
		healthBar.bounds.max = maxHealth;
		healthBar.y -= healthBar.height;
		healthBar.screenCenter(X);
		healthBar.zIndex = 10;
		uiGroup.add(healthBar);
		iconP1 = new HealthIcon(0, 0, player1?.healthIcon, player1?.healthIconData?.isPixel);
		iconP1.flipX = true; // fuck you
		iconP1.zIndex = 15;
		uiGroup.add(iconP1);
		iconP2 = new HealthIcon(0, 0, player2?.healthIcon, player2?.healthIconData?.isPixel);
		iconP2.zIndex = 15;
		uiGroup.add(iconP2);
		
		scoreTxt = new FlxText(0, FlxG.height - 25, FlxG.width, 'Score: idk');
		scoreTxt.setFormat(Paths.ttf('vcr'), 16, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		scoreTxt.y -= scoreTxt.height * .5;
		scoreTxt.borderSize = 1.25;
		uiGroup.add(scoreTxt);
		updateRating();
		debugTxt = new FlxText(0, 12, FlxG.width, '');
		debugTxt.setFormat(Paths.ttf('vcr'), 16, FlxColor.WHITE, CENTER, OUTLINE, FlxColor.BLACK);
		uiGroup.add(debugTxt);
		
		uiGroup.add(opponentStrumline);
		uiGroup.add(playerStrumline);
		
		if (downscroll) {
			for (mem in uiGroup)
				mem.y = FlxG.height - mem.y - mem.height;
		}
		
		var loadedEvents:Array<String> = [];
		for (event in chart.events) {
			var eventName:String = event.name;
			if (!loadedEvents.contains(eventName)) {
				loadedEvents.push(eventName);
				hscripts.loadFromPaths('scripts/events/$eventName.hx');
			}
			events.push(event);
			pushedEvent(event);
		}
		for (i in 0...4) Paths.sound('gameplay/hitsounds/miss$i');
		Paths.sound('gameplay/hitsounds/hitsoundTail');
		Paths.sound('gameplay/hitsounds/hitsoundFail');
		
		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, keyPressEvent);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, keyReleaseEvent);
		
		DiscordRPC.presence.details = '${chart.name} [${chart.difficulty.toUpperCase()}]';
		DiscordRPC.dirty = true;
		
		hscripts.run('createPost');
		sortZIndex();
		
		if (playCountdown) {
			for (snd in ['THREE', 'TWO', 'ONE', 'GO'])
				Paths.sound('gameplay/countdown/funkin/intro$snd');
			for (img in ['ready', 'set', 'go'])
				Paths.image(img);
		}
		conductorInUse.metronome.setBeat(playCountdown ? -5 : -1);
	}
	
	public function loadVocals(path:String, audioSuffix:String = '') {
		for (chara in [player1, player2, player3]) {
			if (chara == null) continue;
			chara.loadVocals(path, audioSuffix);
		}
		if (player1 != null && !player1.vocalsLoaded && player1.character != chart.player1)
			player1.loadVocals(path, audioSuffix, chart.player1);
		if (player2 != null && !player2.vocalsLoaded && player2.character != chart.player2)
			player2.loadVocals(path, audioSuffix, chart.player2);
		if ((player1 == null || !player1.vocalsLoaded) && (player2 == null || !player2.vocalsLoaded)) {
			player1.loadVocals(path, audioSuffix, '');
			if (!player1.vocalsLoaded)
				Log.warning('song vocals not found...');
		}
		for (chara in [player1, player2, player3]) {
			if (chara == null) continue;
			if (chara.vocalsLoaded)
				music.add(chara.vocals);
		}
	}

	override public function update(elapsed:Float) {
		hscripts.run('updatePre', [elapsed, paused, dead]);

		if (FlxG.keys.justPressed.ESCAPE) {
			FlxG.switchState(new FreeplayState());
			return;
		}
		
		if (FlxG.keys.justPressed.SEVEN) {
			CharterState.chart = chart;
			FlxG.switchState(new CharterState());
			return;
		}
		if (FlxG.keys.pressed.SHIFT) {
			if (FlxG.keys.justPressed.R) {
				opponentStrumline.fadeIn();
				playerStrumline.fadeIn();
				
				opponentStrumline.resetLanes();
				playerStrumline.resetLanes();
				events = [];
				for (note in notes) {
					var strumline:Strumline = (note.player ? playerStrumline : opponentStrumline);
					strumline.queueNote(note);
				}
				for (event in chart.events) events.push(event);
				music.pause();
				music.time = 0;
				resetConductor();
				conductorInUse.metronome.setBeat(-5);
				resetScore();
			}
			if (FlxG.keys.justPressed.B) {
				playerStrumline.allowInput = !playerStrumline.allowInput;
				playerStrumline.cpu = !playerStrumline.cpu;
				updateScoreText();
			}
			if (FlxG.keys.justPressed.RIGHT) {
				conductorInUse.songPosition += 3000;
				chart.inst.time = conductorInUse.songPosition;
				syncMusic(false, true);
			}
			if (FlxG.keys.justPressed.LEFT) {
				conductorInUse.songPosition -= 3000;
				chart.inst.time = conductorInUse.songPosition;
				syncMusic(false, true);
			}
			if (FlxG.keys.justPressed.Z) {
				var strumlineY:Float = 50;
				downscroll = !downscroll;
				Options.data.downscroll = !Options.data.downscroll;
				if (Options.data.downscroll) strumlineY = FlxG.height - opponentStrumline.receptorHeight - strumlineY;
				for (strumline in [opponentStrumline, playerStrumline]) {
					strumline.direction += 180;
					strumline.y = strumlineY;
				}
			}
		} else if (!dead) {
			if (FlxG.keys.justPressed.ENTER) {
				paused = !paused;
				var pauseVocals:Bool = (paused || conductorInUse.songPosition < 0);
				if (pauseVocals) {
					music.pause();
				} else {
					music.play(true, conductorInUse.songPosition);
					syncMusic(false, true);
				}
				FlxTimer.globalManager.forEach((timer:FlxTimer) -> { if (!timer.finished) timer.active = !paused; });
				FlxTween.globalManager.forEach((tween:FlxTween) -> { if (!tween.finished) tween.active = !paused; });
			}
			
			if (FlxG.keys.justPressed.R && !paused)
				die();
		}
		
		DiscordRPC.update();
		super.update(elapsed);
		hscripts.run('update', [elapsed, paused, false]); // last argument is for Game over screen

		if (paused) {
			hscripts.run('updatePost', [elapsed, true, false]);
			return;
		}
		
		iconP1.updateBop(elapsed);
		iconP2.updateBop(elapsed);
		iconP1.y = healthBar.barCenter.y - iconP1.frameHeight * .5;
		iconP2.y = healthBar.barCenter.y - iconP2.frameHeight * .5;
		iconP1.x = healthBar.barCenter.x + 60 + (iconP1.frameWidth * iconP1.scale.x - iconP1.defaultSize - iconP1.frameWidth) * .5;
		iconP2.x = healthBar.barCenter.x - 60 - (iconP2.frameWidth * iconP2.scale.x - iconP2.defaultSize + iconP2.frameWidth) * .5;
		
		syncMusic();
		
		var limit:Int = 50; //avoid lags
		while (events.length > 0 && conductorInUse.songPosition >= events[0].msTime && limit > 0) {
			var event:ChartEvent = events.shift();
			triggerEvent(event);
			limit --;
		}
		
		hscripts.run('updatePost', [elapsed, false, false]);
		
		if (!chart.instLoaded && conductorInUse.songPosition >= chart.songLength && !conductorInUse.paused) {
			finishSong();
		}
	}

	public function finishSong() {
		var result:Dynamic = hscripts.run('finishSong');
		if (result == HScript.STOP) {
			conductorInUse.paused = true;
			return;
		}
		FlxG.switchState(() -> new FreeplayState());
	}
	
	public function syncMusic(forceSongpos:Bool = false, forceTrackTime:Bool = false) {
		var syncBase:FunkinSound = music.syncBase;
		if (chart.instLoaded && syncBase != null && syncBase.playing && !conductorInUse.paused) {
			if ((forceSongpos && conductorInUse.songPosition < syncBase.time) || Math.abs(syncBase.time - conductorInUse.songPosition) > 75)
				conductorInUse.songPosition = syncBase.time;
			if (forceTrackTime) {
				if (Math.abs(music.getDisparity(syncBase.time)) > 75)
					music.syncToBase();
			}
		}
	}

	public function pushedEvent(event:ChartEvent) {
		var params:Map<String, Dynamic> = event.params;
		switch (event.name) {
			case 'PlayAnimation':
				var focusChara:Null<Character> = null;
				switch (params['target']) {
					case 'girlfriend', 'gf': focusChara = player3;
					case 'boyfriend', 'bf': focusChara = player1;
					case 'dad': focusChara = player2;
				} if (focusChara != null) focusChara.preloadAnimAsset(params['anim']);
		}
		hscripts.run('eventPushed', [event]);
	}
	
	public function triggerEvent(event:ChartEvent) {
		var params:Map<String, Dynamic> = event.params;
		switch (event.name) {
			case 'FocusCamera':
				var focusCharaInt:Int;
				var focusChara:Null<Character> = null;
				if (params.exists('char')) focusCharaInt = Util.parseInt(params['char']);
				else focusCharaInt = Util.parseInt(params['value']);
				switch (focusCharaInt) {
					case 0: // player focus
						focusChara = player1;
					case 1: // opponent focus
						focusChara = player2;
					case 2: // gf focus
						focusChara = player3;
				}

				if (focusChara != null) {
					focusOnCharacter(focusChara);
				} else {
					camFocusTarget.x = 0;
					camFocusTarget.y = 0;
				}
				if (params.exists('x')) camFocusTarget.x += Util.parseFloat(params['x']);
				if (params.exists('y')) camFocusTarget.y += Util.parseFloat(params['y']);
				FlxTween.cancelTweensOf(camGame.scroll);
				switch (params['ease']) {
					case 'CLASSIC' | null:
						camGame.pauseFollowLerp = false;
					case 'INSTANT':
						camGame.snapToTarget();
						camGame.pauseFollowLerp = false;
					default:
						var duration:Float = Util.parseFloat(params['duration'], 4) * conductorInUse.stepCrochet * .001;
						if (duration <= 0) {
							camGame.snapToTarget();
							camGame.pauseFollowLerp = false;
						} else {
							var easeFunction:Null<Float -> Float> = Reflect.field(FlxEase, params['ease'] ?? 'linear');
							if (easeFunction == null) {
								Log.warning('FocusCamera event: ease function invalid');
								easeFunction = FlxEase.linear;
							}
							camGame.pauseFollowLerp = true;
							FlxTween.tween(camGame.scroll, {x: camFocusTarget.x - FlxG.width * .5, y: camFocusTarget.y - FlxG.height * .5}, duration, {ease: easeFunction, onComplete: (_) -> {
								camGame.pauseFollowLerp = false;
							}});
						}
				}
			case 'ZoomCamera':
				var targetZoom:Float = Util.parseFloat(params['zoom'], 1);
				var direct:Bool = (params['mode'] ?? 'direct' == 'direct');
				targetZoom *= (direct ? FlxCamera.defaultZoom : (stage?.zoom ?? 1));
				camGame.zoomTarget = targetZoom;
				FlxTween.cancelTweensOf(camGame, ['zoom']);
				switch (params['ease']) {
					case 'INSTANT':
						camGame.zoom = targetZoom;
						camGame.pauseZoomLerp = false;
					default:
						var duration:Float = Util.parseFloat(params['duration'], 4) * conductorInUse.stepCrochet * .001;
						if (duration <= 0) {
							camGame.zoom = targetZoom;
							camGame.pauseZoomLerp = false;
						} else {
							var easeFunction:Null<Float -> Float> = Reflect.field(FlxEase, params['ease'] ?? 'linear');
							if (easeFunction == null) {
								Log.warning('FocusCamera event: ease function invalid');
								easeFunction = FlxEase.linear;
							}
							camGame.pauseZoomLerp = true;
							FlxTween.tween(camGame, {zoom: targetZoom}, duration, {ease: easeFunction, onComplete: (_) -> {
								camGame.pauseZoomLerp = false;
							}});
						}
				}
			case 'SetCameraBop':
				var targetRate:Int = Util.parseInt(params['rate'], -1);
				var targetIntensity:Float = Util.parseFloat(params['intensity'], 1);
				hudZoomIntensity = targetIntensity * 2;
				camZoomIntensity = targetIntensity;
				camZoomRate = targetRate;
			case 'PlayAnimation':
				var anim:String = params['anim'];
				var target:String = params['target'];
				var focus:Null<FunkinSprite> = null;
				
				switch (target) {
					case 'dad' | 'opponent': focus = player2;
					case 'girlfriend' | 'gf': focus = player3;
					case 'boyfriend' | 'bf' | 'player': focus = player1;
					default: focus = stage.getProp(target);
				}
				
				if (focus != null && focus.animationExists(anim)) {
					var forced:Bool = params['force'];
					focus.playAnimation(anim, forced);
					
					if (Std.isOfType(focus, Character)) {
						var chara:Character = cast focus;
						chara.specialAnim = forced;
						chara.animReset = 8;
					}
				}
		}
		hscripts.run('eventTriggered', [event]);
	}
	public function focusOnCharacter(chara:Character, center:Bool = false) {
		if (chara != null) {
			camFocusTarget.x = chara.getMidpoint().x + chara.cameraOffset.x + (center ? 0 : chara.stageCameraOffset.x);
			camFocusTarget.y = chara.getMidpoint().y + chara.cameraOffset.y + (center ? 0 : chara.stageCameraOffset.y);
		}
	}
	
	public function stepHitEvent(step:Int) {
		syncMusic(true);
		hscripts.run('stepHit', [step]);
	}
	public function beatHitEvent(beat:Int) {
		try {
			iconP1.bop();
			iconP2.bop();
			stage.beatHit(beat);
		} catch (e:Dynamic) {}

		if (playCountdown) {
			var folder:String = 'funkin';
			switch (beat) {
				case -4:
					FunkinSound.playOnce(Paths.sound('gameplay/countdown/$folder/introTHREE'));
					opponentStrumline.fadeIn();
					playerStrumline.fadeIn();
				case -3:
					popCountdown('ready');
					FunkinSound.playOnce(Paths.sound('gameplay/countdown/$folder/introTWO'));
				case -2:
					popCountdown('set');
					FunkinSound.playOnce(Paths.sound('gameplay/countdown/$folder/introONE'));
				case -1:
					popCountdown('go');
					FunkinSound.playOnce(Paths.sound('gameplay/countdown/$folder/introGO'));
				case 0:
					music.play(true);
					syncMusic(true, true);
				default:
			}
		}
		if (camZoomRate > 0 && beat % camZoomRate == 0)
			bopCamera();
		hscripts.run('beatHit', [beat]);
	}
	public function popCountdown(image:String) {
		var pop = new FunkinSprite().loadTexture(image);
		pop.camera = camHUD;
		pop.screenCenter();
		add(pop);
		FlxTween.tween(pop, {alpha: 0}, conductorInUse.crochet * .001, {ease: FlxEase.cubeInOut, onComplete: (tween:FlxTween) -> {
			remove(pop);
			pop.destroy();
		}});
		hscripts.run('countdownPop', [image, pop]);
	}
	public function barHitEvent(bar:Int) {
		if (camZoomRate < 0)
			bopCamera();
		hscripts.run('barHit', [bar]);
	}
	public function bopCamera() {
		if (!camHUD.pauseZoomLerp)
			camHUD.zoom += .015 * hudZoomIntensity;
		if (!camGame.pauseZoomLerp)
			camGame.zoom += .015 * camZoomIntensity;
	}
	
	public function keyPressEvent(event:KeyboardEvent) {
		var key:FlxKey = event.keyCode;
		var justPressed:Bool = !heldKeys.contains(key);
		if (justPressed)
			heldKeys.push(key);
		
		hscripts.run('keyPressed', [key, justPressed]);
		if (inputDisabled || paused) return;
		if (justPressed) {
			var keybind:Int = Controls.keybindFromArray(keybinds, key);
			var oldTime:Float = conductorInUse.songPosition;
			var newTimeMaybe:Float = conductorInUse.syncTracker?.time ?? oldTime;
			if (conductorInUse.syncTracker != null && conductorInUse.syncTracker.playing)
				conductorInUse.songPosition = newTimeMaybe; // too rigged? (Math.abs(newTimeMaybe) < Math.abs(oldTime) ? newTimeMaybe : oldTime);
			
			if (keybind >= 0) {
				hscripts.run('keybindPressed', [keybind, key]);
				playerStrumline.fireInput(key, true);
			}
			
			conductorInUse.songPosition = oldTime;
		}
	}
	public function keyReleaseEvent(event:KeyboardEvent) {
		var key:FlxKey = event.keyCode;
		heldKeys.remove(key);
		
		hscripts.run('keyReleased', [key]);
		if (inputDisabled || paused) return;
		var keybind:Int = Controls.keybindFromArray(keybinds, key);

		if (keybind >= 0) {
			hscripts.run('keybindReleased', [keybind, key]);
			playerStrumline.fireInput(key, false);
		}
	}

	public function playerNoteEvent(e:NoteEvent) {
		e.targetCharacter = player1;
		e.doSplash = true;
		e.doSpark = true;
		
		if (e.type == NoteEventType.GHOST && Options.data.ghostTapping) {
			e.playAnimation = false;
		} else {
			e.playSound = true;
			e.applyRating = true;
		}

		hscripts.run('playerNoteEventPre', [e]);
		try e.dispatch()
		catch (e:haxe.Exception) Log.error('error dispatching note event -> ${e.message}');
		hscripts.run('playerNoteEvent', [e]);
	}
	public function opponentNoteEvent(e:NoteEvent) {
		e.targetCharacter = player2;
		e.applyRating = false;
		e.playSound = false;
		e.doSplash = false;
		e.doSpark = false;

		hscripts.run('opponentNoteEventPre', [e]);
		try e.dispatch()
		catch (e:haxe.Exception) Log.error('error dispatching note event -> ${e.message}');
		hscripts.run('opponentNoteEvent', [e]);
	}
	public dynamic function comboBroken(oldCombo:Int) {
		popCombo(0);
		var result:Dynamic = hscripts.run('comboBroken');
		if (result != HScript.STOP && oldCombo >= 10 && player3 != null) player3.playAnimationSteps('sad', true, 8);
	}
	public function popCombo(combo:Int) {
		var tempCombo:Int = combo;
		var nums:Array<Int> = [];
		while (tempCombo >= 1) {
			nums.unshift(tempCombo % 10);
			tempCombo = Std.int(tempCombo / 10);
		}
		while (nums.length < 3) nums.unshift(0);
		
		var xOffset:Float = -nums.length * .5 + .5;
		for (i => num in nums) {
			var popNum:FunkinSprite = popRating('num$num', .5, 2);
			popNum.setPosition(popNum.x + (i + xOffset) * 43, popNum.y + 80);
			popNum.acceleration.y = FlxG.random.int(200, 300);
			popNum.velocity.y = -FlxG.random.int(140, 160);
			popNum.velocity.x = FlxG.random.float(-5, 5);
		}
	}
	public function popRating(ratingString:String, scale:Float = .7, beats:Float = 1) {
		var rating:FunkinSprite = new FunkinSprite(0, 0);
		rating.loadTexture(ratingString);
		rating.scale.set(scale, scale);
		rating.setOffset(rating.frameWidth * .5, rating.frameHeight * .5);

		ratingGroup.add(rating);
		FlxTween.tween(rating, {alpha: 0}, .2, {onComplete: (tween:FlxTween) -> {
			ratingGroup.remove(rating, true);
			rating.destroy();
		}, startDelay: conductorInUse.crochet * .001 * beats});
		return rating;
	}
	
	public function set_maxHealth(newHealth:Float) {
		health = Math.min(health, newHealth);
		healthBar.bounds.max = newHealth;
		healthBar.updateBars();
		return maxHealth = newHealth;
	}
	public function set_health(newHealth:Float) {
		newHealth = FlxMath.bound(newHealth, 0, maxHealth);
		if (newHealth >= healthBar.bounds.max - .15) {
			if (iconP1.animation.name != 'winning') iconP1.playAnimation('winning');
			if (iconP2.animation.name != 'losing') iconP2.playAnimation('losing');
		} else if (newHealth <= healthBar.bounds.min + .15) {
			if (iconP1.animation.name != 'losing') iconP1.playAnimation('losing');
			if (iconP2.animation.name != 'winning') iconP2.playAnimation('winning');
		} else {
			if (iconP1.animation.name != 'neutral') iconP1.playAnimation('neutral');
			if (iconP2.animation.name != 'neutral') iconP2.playAnimation('neutral');
		}
		if (newHealth <= 0 && !godmode && !dead)
			die(false);
		return health = newHealth;
	}
	public function die(instant:Bool = true) {
		var result:Dynamic = hscripts.run('deathPre', [instant]);
		if (result == HScript.STOP)
			return;
		
		conductorInUse.paused = true;
		focusOnCharacter(player1);
		inputDisabled = true;
		dead = true;
		if (player1 != null) {
			player1.bop = false;
		}
		FlxTween.cancelTweensOf(camGame.scroll);
		FlxTween.cancelTweensOf(camGame);
		camGame.pauseFollowLerp = false;
		
		gameOver = new GameOverSubState(instant);
		function actuallyDie() {
			music.stop();
			camGame.zoomTarget = gameOver.cameraZoom * stage.zoom;
			camGame.zoomFollowLerp = camGame.followLerp = 3;
			camGame.pauseZoomLerp = false;
			openSubState(gameOver);
		}
		
		if (instant) {
			focusOnCharacter(player1, true);
			actuallyDie();
		} else {
			camGame.followLerp = 10;
			camGame.pauseZoomLerp = true;
			
			final deathDuration:Float = .4;
			music.fadeOut(deathDuration);
			
			FlxTween.tween(camGame, {zoom: camGame.zoom + .3}, deathDuration, {ease: FlxEase.elasticOut, onComplete: (_) -> { actuallyDie(); }});
		}
	}
	public function resetScore() {
		score = accuracyMod = accuracyDiv = misses = totalHits = totalNotes = combo = 0;
		health = .5;
		updateRating();
	}
	public function updateRating() {
		percent = (accuracyMod / Math.max(1, accuracyDiv)) * 100;
		updateScoreText();
	}
	public function updateScoreText() {
		var scoreStr:String = Util.thousandSep(Std.int(score));
		if (Options.data.xtendScore) {
			var accuracyString:String = 'NA';
			if (totalNotes > 0) accuracyString = Util.padDecimals(percent, 2);
			if (playerStrumline.cpu) accuracyString = 'BOT';
			scoreTxt.text = '$accuracyString% | Misses: $misses | Score: $scoreStr';
		} else {
			scoreTxt.text = 'Score: $scoreStr';
			if (playerStrumline.cpu) scoreTxt.text = 'BOT ${scoreTxt.text}';
		}
		hscripts.run('updateScoreText');
	}
	public function set_combo(newCombo:Int) {
		if (combo > 0 && newCombo == 0) comboBroken(combo);
		return combo = newCombo;
	}
	
	override public function destroy() {
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, keyPressEvent);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, keyReleaseEvent);
		Main.watermark.visible = true;
		conductorInUse.paused = false;
		super.destroy();
	}
}