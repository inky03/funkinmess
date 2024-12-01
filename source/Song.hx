package;

import Note;
import Conductor.Metronome;
import Conductor.TempoChange;
import Conductor.TimeSignature;

import haxe.Exception;
import moonchart.formats.StepMania;
import moonchart.formats.BasicFormat;
import moonchart.formats.fnf.FNFVSlice;
import moonchart.formats.StepManiaShark;
import moonchart.parsers.StepManiaParser;

using StringTools;

/*
important note (moonchart):
stepsPerBeat is INCORRECT
denominator indicates the value of a note: x/4 means every beat has the time of a quarter note, x/8 an eighth note, and so on
steps are not a thing in music theory in the definition friday night funkin' / fl studio uses.
*/

/*
LOADING A SONG:
for legacy / psych engine format ... Song.loadLegacySong('songName', 'difficulty')
for modern (fnf 0.3.0+) format ... Song.loadModernSong('songName', 'difficulty', ?'suffix')
for simfile (stepmania) ... Song.loadStepMania('songName', 'difficulty')
*/

class Song {
	public var path:String = '';
	public var name:String = '';
	public var artist:String = '';
	public var difficulty:String = '';

	public var chart:Any; //BasicFormat?
	public var json:Dynamic;
	
	public var keyCount:Int = 4;
	public var scrollSpeed:Float = 1;
	public var initialBpm:Float = 100;
	public var notes:Array<SongNote> = [];
	public var events:Array<SongEvent> = [];
	public var tempoChanges:Array<TempoChange> = [new TempoChange(-4, 100, new TimeSignature())];

	public var instLoaded:Bool;
	public var inst:FlxSound;
	public var songLength:Float = 0;
	public var audioSuffix:String = '';

	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var player3:String = 'gf';
	public var stage:String;
	
	public function new(path:String, keyCount:Int = 4) {
		this.path = path;
		this.keyCount = keyCount;
		
		instLoaded = false;
		inst = new FlxSound();
		FlxG.sound.list.add(inst);
	}
	
	public static function loadJson(path:String, difficulty:String = 'normal') {
		var jsonPathD:String = 'data/songs/$path/$path';
		var diffSuffix:String = '-$difficulty';
		
		var jsonPath:String = '$jsonPathD$diffSuffix.json';
		if (!Paths.exists(jsonPath)) jsonPath = jsonPathD;
		if (Paths.exists(jsonPath)) {
			var content:String = Paths.text(jsonPath);
			var jsonData:Dynamic = TJSON.parse(content);
			return jsonData;
		} else {
			Log.warning('chart JSON not found... (chart not generated)');
			Log.minor('verify path:');
			Log.minor('- chart: $jsonPath');
			return null;
		}
	}
	
	public static function loadAutoDetect(path:String, difficulty:String = 'hard', suffix:String = '') {
		difficulty = difficulty.toLowerCase();
		Log.minor('detecting format from song "$path"');
		
		var songPath:String = 'data/songs/$path/$path';
		var modernChartPath:String = Util.pathSuffix('$songPath-chart', suffix) + '.json';
		var modernMetaPath:String = Util.pathSuffix('$songPath-metadata', suffix) + '.json';
		var sharkChartPath:String = Util.pathSuffix(songPath, suffix) + '.ssc';
		var smChartPath:String = Util.pathSuffix(songPath, suffix) + '.sm';
		var legacyChartPath:String = Util.pathSuffix(Util.pathSuffix(songPath, difficulty), suffix) + '.json';
		if (Paths.exists(modernChartPath) && Paths.exists(modernMetaPath)) {
			return loadModernSong(path, difficulty, suffix);
		} else if (Paths.exists(sharkChartPath) || Paths.exists(smChartPath)) {
			return loadStepMania(path, difficulty, suffix);
		} else if (Paths.exists(legacyChartPath)) {
			return loadLegacySong(path, difficulty, suffix);
		} else {
			Log.warning('chart files of any type not found... (chart not generated)');
			Log.minor('verify paths:');
			Log.minor('- modern:');
			Log.minor('  - chart: $modernChartPath');
			Log.minor('  - metadata: $modernMetaPath');
			Log.minor('- stepmania sm: $smChartPath');
			Log.minor('- stepmania ssc: $sharkChartPath');
			Log.minor('- legacy: $legacyChartPath');
			return new Song(path, 4);
		}
	}
	
	public static function loadStepMania(path:String, difficulty:String = 'Hard', suffix:String = '') { // TODO: these could just not be static
		difficulty = difficulty.toLowerCase();
		Log.minor('loading StepMania simfile "$path" with difficulty "$difficulty"${suffix == '' ? '' : ' ($suffix)'}');

		var songPath:String = 'data/songs/$path/$path';
		var sscPath:String = '${Util.pathSuffix(songPath, suffix)}.ssc';
		var smPath:String = '$songPath.sm';
		var useShark:Bool = Paths.exists(sscPath);
		var song:Song = new Song(path, 4); // todo: sm multikey (implement multikey in the first place)

		if (!Paths.exists(smPath) && !useShark) {
			Log.warning('sm or ssc file not found... (chart not generated)');
			Log.minor('verify path:');
			Log.minor('- chart: $smPath OR $sscPath');
			return song;
		}

		var time = Sys.time();
		var shark:StepManiaShark;
		try {
			if (useShark) { // goofy but who cares (hint: also me)
				var sscContent:String = Paths.text(sscPath);
				shark = new StepManiaShark().fromStepManiaShark(sscContent);
			} else {
				var smContent:String = Paths.text(smPath);
				var sm:StepMania = new StepMania().fromStepMania(smContent);
				shark = new StepManiaShark().fromFormat(sm);
			}
			song.loadGeneric(shark, difficulty);

			var tempMetronome:Metronome = new Metronome();
			tempMetronome.tempoChanges = song.tempoChanges;
			var notes:Array<BasicNote> = shark.getNotes(difficulty);
			var dance:StepManiaDance = @:privateAccess shark.resolveDance(notes);
			for (note in notes) {
				tempMetronome.setMS(note.time + 1);
				var isPlayer:Bool = (dance == SINGLE ? note.lane < 4 : note.lane >= 4);
				var stepCrochet:Float = tempMetronome.getCrochet(tempMetronome.bpm, tempMetronome.timeSignature.denominator) * .25;
				song.notes.push({player: isPlayer, msTime: note.time, laneIndex: Std.int(note.lane % 4), msLength: note.length});
			}

			song.findSongLength();
			Log.info('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch (e:Exception) {
			Log.error('chart error... -> <<< ${e.details()} >>>');
			return song;
		}
		
		return song;
	}

	// suffix is for playable characters
	public static function loadModernSong(path:String, difficulty:String = 'hard', suffix:String = '') {
		difficulty = difficulty.toLowerCase();
		Log.minor('loading modern FNF song "$path" with difficulty "$difficulty"${suffix == '' ? '' : ' ($suffix)'}');

		var songPath:String = 'data/songs/$path/$path';
		var chartPath:String = '${Util.pathSuffix('$songPath-chart', suffix)}.json';
		var metaPath:String = '${Util.pathSuffix('$songPath-metadata', suffix)}.json';
		var song:Song = new Song(path, 4);

		if (!Paths.exists(chartPath) || !Paths.exists(metaPath)) {
			Log.warning('chart or metadata JSON not found... (chart not generated)');
			Log.minor('verify paths:');
			Log.minor('- chart: $chartPath');
			Log.minor('- metadata: $metaPath');
			return song;
		}

		var time = Sys.time();
		var vslice:FNFVSlice;
		try {
			var chartContent:String = Paths.text(chartPath);
			var metaContent:String = Paths.text(metaPath);
			vslice = new FNFVSlice().fromJson(chartContent, metaContent);
			song.loadGeneric(vslice, difficulty);

			var tempMetronome:Metronome = new Metronome();
			tempMetronome.tempoChanges = song.tempoChanges;
			var notes:Array<BasicNote> = vslice.getNotes(difficulty);
			for (note in notes) {
				tempMetronome.setMS(note.time + 1);
				var stepCrochet:Float = tempMetronome.getCrochet(tempMetronome.bpm, tempMetronome.timeSignature.denominator) * .25;
				song.notes.push({player: note.lane >= 4, msTime: note.time, laneIndex: Std.int(note.lane % 4), msLength: note.length - stepCrochet});
			}

			Log.info('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch (e:Exception) {
			Log.error('chart error... -> <<< ${e.details()} >>>');
			return song;
		}

		var meta:BasicMetaData = vslice.getChartMeta();
		song.player1 = meta.extraData['FNF_P1'] ?? 'bf';
		song.player2 = meta.extraData['FNF_P2'] ?? 'dad';
		song.player3 = meta.extraData['FNF_P3'] ?? 'gf';
		song.stage = meta.extraData['FNF_STAGE'] ?? 'placeholder';
		time = Sys.time();
		song.audioSuffix = suffix;
		song.findSongLength();

		return song;
	}

	public function loadGeneric(format:Dynamic, difficulty:String, parseEvents:Bool = true) {
		this.difficulty = difficulty;
		this.chart = format;

		var meta:BasicMetaData = format.getChartMeta();
		this.scrollSpeed = meta.scrollSpeeds[difficulty] ?? 1;
		this.artist = meta.extraData['SONG_ARTIST'] ?? '';
		this.name = meta.title;

		var bpmChanges:Array<BasicBPMChange> = meta.bpmChanges;
		var tempMetronome:Metronome = new Metronome();
		this.tempoChanges = [];
		this.initialBpm = bpmChanges[0].bpm;
		tempMetronome.tempoChanges = this.tempoChanges;
		for (i => change in bpmChanges) {
			var beat:Float = tempMetronome.convertMeasure(change.time, MS, BEAT);
			var timeSig:Null<TimeSignature> = null;
			if (change.beatsPerMeasure > 0 && change.stepsPerBeat > 0)
				timeSig = new TimeSignature(Std.int(change.beatsPerMeasure), Std.int(change.stepsPerBeat));
			else if (i == 0) // apply default time signature to first bpm change hehe
				timeSig = new TimeSignature();
			this.tempoChanges.push(new TempoChange(beat, change.bpm, timeSig));
		}

		if (parseEvents) {
			var events:Array<BasicEvent> = format.getEvents();
			for (event in events) {
				var newParams:Map<String, Dynamic> = [];
				if (Reflect.isObject(event.data)) {
					for (param in Reflect.fields(event.data))
						newParams[param] = Reflect.field(event.data, param);
				} else
					newParams['value'] = event.data;
				this.events.push({name: event.name, msTime: event.time, params: newParams});
			}
		}
		
		this.sort();
		return this;
	}
	public function findSongLength() {
		if (instLoaded) {
			this.songLength = inst.length;
		} else {
			var lastNote:SongNote = notes[notes.length - 1];
			this.songLength = (lastNote == null ? 0 : lastNote.msTime + lastNote.msLength) + 500;
		}
		return this.songLength;
	}
	
	public static function loadLegacySong(path:String, difficulty:String = 'normal', suffix:String = '', keyCount:Int = 4) { // move to moonchart format???
		difficulty = difficulty.toLowerCase();
		Log.minor('loading legacy FNF song "$path" with difficulty "$difficulty"${suffix == '' ? '' : ' ($suffix)'}');
		
		var song = new Song(path, keyCount);
		song.json = Song.loadJson(path, difficulty);
		song.difficulty = difficulty;
		
		if (song.json == null) return song;
		var fromSong:Bool = (!Std.isOfType(song.json.song, String));
		if (fromSong) song.json = song.json.song; // probably move song.json to song.chart?
		
		var time = Sys.time();
		try {
			var eventsPath:String = 'data/songs/$path/events.json';
			var eventContent:Null<String> = Paths.text(eventsPath);
			if (eventContent != null) {
				Log.minor('loading events from "$eventsPath"');
				var eventJson:Dynamic = TJSON.parse(eventContent);
				if (eventJson.song != null && !Std.isOfType(eventJson.song, String)) eventJson = eventJson.song;
				if (song.json.events == null) song.json.events = [];
				var eventBlobs:Array<Array<Dynamic>> = eventJson.events;
				var songEventBlobs:Array<Array<Dynamic>> = song.json.events;
				for (eventBlob in eventBlobs) songEventBlobs.push(eventBlob);
			}
			
			song.name = song.json.song;
			song.initialBpm = song.json.bpm;
			song.tempoChanges = [new TempoChange(-4, song.initialBpm, new TimeSignature())];
			song.scrollSpeed = song.json.speed;
			
			var ms:Float = 0;
			var beat:Float = 0;
			var sectionNumerator:Float = 0;
			var osectionNumerator:Float = 0;
			
			var bpm:Float = song.initialBpm;
			var crochet:Float = 60000 / song.initialBpm;
			var stepCrochet:Float = crochet * .25;
			var focus:Int = -1;
			
			var sections:Array<LegacySongSection> = song.json.notes;
			if (song.json.events != null) { // todo: implement events.json
				var eventBlobs:Array<Array<Dynamic>> = song.json.events;
				for (eventBlob in eventBlobs) {
					var eventTime:Float = eventBlob[0];
					var events:Array<Array<String>> = eventBlob[1];
					for (event in events) {
						var songEvent:SongEvent = {name: event[0], msTime: eventTime, params: ['value1' => event[1], 'value2' => event[2]]};
						song.events.push(songEvent);
					}
				}
			}
			var tempMetronome:Metronome = new Metronome();
			tempMetronome.tempoChanges = song.tempoChanges;
			for (section in sections) {
				var sectionFocus:Int = (section.gfSection ? 2 : (section.mustHitSection ? 0 : 1));
				if (focus != sectionFocus) {
					focus = sectionFocus;
					song.events.push({name: 'FocusCamera', msTime: ms, params: ['char' => focus]});
				}
				
				var sectionDenominator:Int = 4;
				var sectionNumerator:Float = section.sectionBeats;
				if (sectionNumerator == 0) sectionNumerator = section.lengthInSteps * .25;
				if (sectionNumerator == 0) sectionNumerator = 4;
				while (sectionNumerator % 1 > 0 && sectionDenominator < 32) {
					sectionNumerator *= 2;
					sectionDenominator *= 2;
				}
				var changeSign:Bool = (sectionNumerator != osectionNumerator);
				if (section.changeBPM || changeSign) {
					osectionNumerator = sectionNumerator;
					if (section.changeBPM) bpm = section.bpm;
					crochet = 60000 / bpm / sectionDenominator * 4;
					stepCrochet = crochet * .25;
					
					song.tempoChanges.push(new TempoChange(beat, section.changeBPM ? section.bpm : null, changeSign ? new TimeSignature(Std.int(sectionNumerator), sectionDenominator) : null));
				}
				beat += sectionNumerator;
				ms += sectionNumerator * crochet;
				
				for (dataNote in section.sectionNotes) {
					var noteTime:Float = dataNote[0];
					var noteData:Int = Std.int(dataNote[1]);
					if (noteData < 0) { // old psych event
						song.events.push({name: dataNote[2], msTime: noteTime, params: ['value1' => dataNote[3], 'value2' => dataNote[4]]});
						continue;
					}

					var noteLength:Float = dataNote[2];
					var noteKind:Dynamic = dataNote[3];
					if (!Std.isOfType(noteKind, String)) noteKind = '';
					var playerNote:Bool;
					if (fromSong) {
						playerNote = ((noteData < keyCount) == section.mustHitSection);
					} else { // assume psych 1.0
						playerNote = (noteData < keyCount);
					}
					
					song.notes.push({player: playerNote, msTime: noteTime, laneIndex: noteData % keyCount, msLength: noteLength, kind: noteKind});
				}
			}
			song.sort();
			song.findSongLength();

			song.player1 = song.json.player1;
			song.player2 = song.json.player2;
			song.player3 = song.json.player3 ?? song.json.gfVersion ?? 'gf';
			song.stage = song.json.stage;

			Log.info('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch(e:Exception) {
			Log.error('chart error... -> <<< ${e.details()} >>>');
		}
		
		return song;
	}

	public function generateNotes():Array<Note> {
		var noteArray:Array<Note> = [];
		var tempMetronome:Metronome = new Metronome();
		tempMetronome.tempoChanges = this.tempoChanges;
		for (note in notes) {
			tempMetronome.setMS(note.msTime);
			var hitNote:Note = new Note(note.player, note.msTime, note.laneIndex, note.msLength, note.kind);
			noteArray.push(hitNote);
			
			if (hitNote.msLength > 0) { //hold bits
				var endMs:Float = note.msTime + note.msLength;
				var bitTime:Float = note.msTime;
				while (bitTime < endMs) {
					tempMetronome.setStep(Std.int(tempMetronome.step + .05) + 1);
					var newTime:Float = tempMetronome.ms;
					if (bitTime < note.msTime) {
						Log.warning('??? $bitTime < ${note.msTime} (sustain bit off by ${note.msTime - bitTime}ms)');
						bitTime = newTime;
						break;
					}
					var bitLength:Float = Math.min(newTime - bitTime, endMs - bitTime);
					var holdBit:Note = new Note(note.player, bitTime, note.laneIndex, bitLength, note.kind, true);
					hitNote.children.push(holdBit);
					holdBit.parent = hitNote;
					noteArray.push(holdBit);
					bitTime = newTime;
				}
				var endBit:Note = new Note(note.player, endMs, note.laneIndex, 0, note.kind, true);
				hitNote.children.push(endBit);
				noteArray.push(endBit);
				
				endBit.parent = hitNote;
				hitNote.tail = endBit;
			}
		}
		return noteArray;
	}
	
	public function loadMusic(path:String, overwrite:Bool = true) { // this could be better
		if (instLoaded && !overwrite) return true;
		var instPath:String = path + Util.pathSuffix('Inst', audioSuffix);
		// Log.minor('attempting to load instrumental from $instPath...');
		try {
			inst.loadEmbedded(Paths.ogg(instPath));
			if (inst.length > 0) {
				songLength = inst.length;
				instLoaded = true;
				inst.play();
				inst.stop();
				Log.info('instrumental loaded!!');
				return true;
			}
		} catch (e:Exception) {
			Log.error('error when loading instrumental -> ${e.message}');
			instLoaded = false;
		}
		return false;
	}
	
	public function sort() {
		notes.sort((a, b) -> Std.int(a.msTime - b.msTime));
		events.sort((a, b) -> Std.int(a.msTime - b.msTime));
	}
}

@:structInit class SongNote {
	public var laneIndex:Int;
	public var msTime:Float = 0;
	public var kind:String = '';
	public var msLength:Float = 0;
	public var player:Bool = true;
}
@:structInit class SongEvent {
	public var name:String;
	public var msTime:Float;
	public var params:Map<String, Any>;
}

typedef LegacySongSection = {
	var sectionNotes:Array<Array<Any>>;
	var sectionBeats:Float;
	var lengthInSteps:Float;
	var mustHitSection:Bool;
	var gfSection:Bool;
	var changeBPM:Bool;
	var bpm:Float;
}