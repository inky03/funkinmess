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

/*
important note (moonchart):
stepsPerBeat is INCORRECT
denominator indicates the value of a note: x/4 means every beat has the time of a quarter note, x/8 an eighth note, and so on
steps are not a thing in music theory in the definition friday night funkin' / fl studio uses.
*/

class Song {
	public var path:String = '';
	public var name:String = '';
	public var artist:String = '';

	public var chart:Any; //BasicFormat?
	public var json:Dynamic;
	public var initialBpm:Float = 100;
	public var keyCount:Int = 4;
	public var notes:Array<Note> = [];
	public var events:Array<SongEvent> = [];
	public var tempoChanges:Array<TempoChange> = [new TempoChange(0, 100, new TimeSignature())];
	public var scrollSpeed:Float = 1;

	public var instLoaded:Bool;
	public var vocalsLoaded:Bool;
	public var instTrack:FlxSound;
	public var vocalTrack:FlxSound;
	public var oppVocalsLoaded:Bool;
	public var oppVocalTrack:FlxSound;
	public var audioSuffix:String = '';

	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var player3:String = 'gf';
	
	public function new(path:String, keyCount:Int = 4) {
		this.path = path;
		this.keyCount = keyCount;
		
		instLoaded = false;
		instTrack = new FlxSound();
		vocalTrack = new FlxSound();
		oppVocalTrack = new FlxSound();
		FlxG.sound.list.add(instTrack);
		FlxG.sound.list.add(vocalTrack);
		FlxG.sound.list.add(oppVocalTrack);
	}
	
	public static function loadJson(path:String, difficulty:String = 'normal') {
		var jsonPathD:String = 'data/$path/$path';
		var diffSuffix:String = '-$difficulty';
		
		var jsonPath:String = '$jsonPathD$diffSuffix.json';
		if (!Paths.exists(jsonPath)) jsonPath = jsonPathD;
		if (Paths.exists(jsonPath)) {
			var content:String = Paths.text(jsonPath);
			var jsonData:Dynamic = TJSON.parse(content);
			return jsonData;
		} else {
			Sys.println('chart JSON not found... (chart not generated)');
			Sys.println('verify path:');
			Sys.println('- chart: $jsonPath');
			return null;
		}
	}
	
	public static function loadStepMania(path:String, difficulty:String = 'Hard') { // TODO: this could just not be static
		Sys.println('loading StepMania simfile "$path" with difficulty "$difficulty"');

		var songPath:String = 'data/$path/$path';
		var sscPath:String = '$songPath.ssc';
		var smPath:String = '$songPath.sm';
		var useShark:Bool = Paths.exists(sscPath);
		var song:Song = new Song(path, 4); // todo: sm multikey (implement multikey in the first place)

		if (!Paths.exists(smPath) && !useShark) {
			Sys.println('sm or ssc file not found... (chart not generated)');
			Sys.println('verify path:');
			Sys.println('- chart: $smPath OR $sscPath');
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
			Note.baseMetronome = tempMetronome;
			var notes:Array<BasicNote> = shark.getNotes(difficulty);
			var dance:StepManiaDance = @:privateAccess shark.resolveDance(notes);
			for (note in notes) {
				tempMetronome.setMS(note.time + 1);
				var isPlayer:Bool = (dance == SINGLE ? note.lane < 4 : note.lane >= 4);
				var stepCrochet:Float = tempMetronome.getCrochet(tempMetronome.bpm, tempMetronome.timeSignature.denominator) * .25;
				for (note in generateNotes(isPlayer, note.time, Std.int(note.lane % 4), '', note.length, stepCrochet))
					song.notes.push(note);
			}
			Note.baseMetronome = Conductor.metronome;

			Sys.println('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch (e:Exception) {
			Sys.println('chart error... -> <<< ${e.details()} >>>');
			return song;
		}

		time = Sys.time();
		song.loadMusic('data/$path/');
		song.loadMusic('songs/$path/');
		Sys.println(song.instLoaded ? ('music loaded! (${Math.round((Sys.time() - time) * 1000) / 1000}s)') : ('music failed to load...'));

		return song;
	}

	// suffix is for playable characters
	public static function loadModernSong(path:String, difficulty:String = 'hard', suffix:String = '') {
		Sys.println('loading modern FNF song "$path" with difficulty "$difficulty"${suffix == '' ? '' : ' ($suffix)'}');

		var songPath:String = 'data/$path/$path';
		var chartPath:String = '${Util.pathSuffix('$songPath-chart', suffix)}.json';
		var metaPath:String = '${Util.pathSuffix('$songPath-metadata', suffix)}.json';
		var song:Song = new Song(path, 4);

		if (!Paths.exists(chartPath) || !Paths.exists(metaPath)) {
			Sys.println('chart or metadata JSON not found... (chart not generated)');
			Sys.println('verify paths:');
			Sys.println('- chart: $chartPath');
			Sys.println('- metadata: $metaPath');
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
			Note.baseMetronome = tempMetronome;
			var notes:Array<BasicNote> = vslice.getNotes(difficulty);
			for (note in notes) {
				tempMetronome.setMS(note.time + 1);
				var stepCrochet:Float = tempMetronome.getCrochet(tempMetronome.bpm, tempMetronome.timeSignature.denominator) * .25;
				for (note in generateNotes(note.lane >= 4, note.time, Std.int(note.lane % 4), '', note.length - stepCrochet, stepCrochet))
					song.notes.push(note);
			}
			Note.baseMetronome = Conductor.metronome;

			Sys.println('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch (e:Exception) {
			Sys.println('chart error... -> <<< ${e.details()} >>>');
			return song;
		}

		var meta:BasicMetaData = vslice.getChartMeta();
		song.player1 = meta.extraData['FNF_P1'] ?? 'bf';
		song.player2 = meta.extraData['FNF_P2'] ?? 'dad';
		song.player3 = meta.extraData['FNF_P3'] ?? 'gf';
		time = Sys.time();
		song.audioSuffix = suffix;
		song.loadMusic('data/$path/', song.player1, song.player2);
		song.loadMusic('songs/$path/', song.player1, song.player2);
		Sys.println(song.instLoaded ? ('music loaded! (${Math.round((Sys.time() - time) * 1000) / 1000}s)') : ('music failed to load...'));

		return song;
	}

	public function loadGeneric(format:Dynamic, difficulty:String, parseEvents:Bool = true) {
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
		bpmChanges.sort((a, b) -> Std.int(a.time - b.time));
		for (i => change in bpmChanges) {
			var beat:Float = tempMetronome.convertMeasure(change.time, MS, BEAT);
			var timeSig:Null<TimeSignature> = null;
			if (change.beatsPerMeasure > 0 && change.stepsPerBeat > 0)
				timeSig = new TimeSignature(Std.int(change.beatsPerMeasure), Std.int(change.stepsPerBeat));
			else if (i == 0) // apply default time signature to first bpm change hehe
				timeSig = new TimeSignature();
			this.tempoChanges.push(new TempoChange(beat, change.bpm, timeSig));
			trace('$beat -> ${change.bpm} bpm, ${timeSig == null ? '' : timeSig.toString()}');
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
		return this;
	}
	
	public static function loadLegacySong(path:String, difficulty:String = 'normal', keyCount:Int = 4) { // move to moonchart format???
		Sys.println('loading legacy FNF song "${path}" with difficulty "$difficulty"');
		
		var song = new Song(path, keyCount);
		song.json = Song.loadJson(path, difficulty);
		
		if (song.json == null) return song;
		var fromSong:Bool = (!Std.isOfType(song.json.song, String));
		if (fromSong) song.json = song.json.song; // probably move song.json to song.chart?
		
		var time = Sys.time();
		try {
			song.name = song.json.song;
			song.initialBpm = song.json.bpm;
			song.tempoChanges = [new TempoChange(0, song.initialBpm, new TimeSignature())];
			song.scrollSpeed = song.json.speed;
			
			var ms:Float = 0;
			var beat:Float = 0;
			var sectionNumerator:Float = 0;
			var osectionNumerator:Float = 0;
			
			var bpm:Float = song.initialBpm;
			var crochet:Float = 60000 / song.initialBpm;
			var stepCrochet:Float = crochet * .25;
			var focus:Int = -1;
			
			var prevMetronome:Metronome = Conductor.metronome;
			var sections:Array<LegacySongSection> = song.json.notes;
			if (song.json.events != null) { // todo: implement events.json
				var eventBlobs:Array<Array<Dynamic>> = song.json.events;
				for (eventBlob in eventBlobs) {
					var eventTime:Float = eventBlob[0];
					var events:Array<Array<String>> = eventBlob[1];
					for (event in events) {
						song.events.push({name: event[0], msTime: eventTime, params: ['value1' => event[1], 'value2' => event[2]]});
					}
				}
			}
			var tempMetronome:Metronome = new Metronome();
			tempMetronome.tempoChanges = song.tempoChanges;
			Note.baseMetronome = tempMetronome;
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
					
					for (note in generateNotes(playerNote, noteTime, noteData % keyCount, noteKind, noteLength, stepCrochet)) song.notes.push(note);
				}
			}
			song.sortNotes();
			Note.baseMetronome = Conductor.metronome;

			song.player1 = song.json.player1;
			song.player2 = song.json.player2;
			song.player3 = song.json.player3 ?? song.json.gfVersion ?? 'gf';

			Sys.println('chart loaded successfully! (${Math.round((Sys.time() - time) * 1000) / 1000}s)');
		} catch(e:Exception) {
			Sys.println('chart error... -> <<< ${e.details()} >>>');
		}

		time = Sys.time();
		song.loadMusic('data/$path/');
		song.loadMusic('songs/$path/');
		Sys.println(song.instLoaded ? ('music loaded! (${Math.round((Sys.time() - time) * 1000) / 1000}s)') : ('music failed to load...'));

		return song;
	}
	
	public static function generateNotes(playerNote:Bool, noteTime:Float, noteData:Int, noteKind:String = '', noteLength:Float = 0, stepCrochet:Float = 1000) {
		var notes:Array<Note> = [];
		var hitNote:Note = new Note(playerNote, noteTime, noteData, noteLength, noteKind);
		notes.push(hitNote);
		
		if (hitNote.msLength > 0) { //hold bits
			var holdBits:Float = noteLength / stepCrochet;
			for (i in 0...Math.ceil(holdBits)) {
				var bitTime:Float = i * stepCrochet;
				var bitLength:Float = stepCrochet;
				if (i == Math.ceil(holdBits - 1)) bitLength = (noteLength - bitTime);
				var holdBit:Note = new Note(playerNote, noteTime + bitTime, noteData, bitLength, noteKind, true);
				hitNote.children.push(holdBit);
				holdBit.parent = hitNote;
				notes.push(holdBit);
			}
			var endBit:Note = new Note(playerNote, noteTime + noteLength, noteData, 0, noteKind, true);
			hitNote.children.push(endBit);
			notes.push(endBit);
			
			endBit.parent = hitNote;
			hitNote.tail = endBit;
		}
		
		return notes;
	}
	
	public function loadMusic(path:String, player:String = '', opponent:String = '') { // this could be better
		if (instLoaded) return true;
		try {
			instTrack.loadEmbedded(Paths.ogg(path + Util.pathSuffix('Inst', audioSuffix)));

			vocalTrack.loadEmbedded(Paths.ogg(path + Util.pathSuffix('Voices', audioSuffix)));
			oppVocalTrack.loadEmbedded(Paths.ogg(path + Util.pathSuffix(Util.pathSuffix('Voices', opponent), audioSuffix)));
			if (vocalTrack.length == 0) vocalTrack.loadEmbedded(Paths.ogg(path + Util.pathSuffix(Util.pathSuffix('Voices', player), audioSuffix)));

			instLoaded = (instTrack.length > 0);
			vocalsLoaded = (vocalTrack.length > 0);
			oppVocalsLoaded = (oppVocalTrack.length > 0);
			return true;
		} catch (e:Any)
			return false;
	}
	
	public function sortNotes() {
		notes.sort((a, b) -> {
			var ord:Int = Std.int(a.msTime - b.msTime);
			if (ord == 0 && !a.isHoldPiece && b.isHoldPiece) return -1;
			return ord;
		});
	}
}

typedef SongEvent = {
	var name:String;
	var msTime:Float;
	var params:Map<String, Any>;
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