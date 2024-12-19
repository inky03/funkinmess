package;

using Lambda;

class Scoring {
	public static var safeFrames:Float = 10;
	public static var holdLeniencyMS:Float = 75;
	
	public static function legacyDefault() {
		var windows:Array<HitWindow> = [
			new HitWindow('sick', 	350, 	.2, 	1),
			new HitWindow('good', 	200, 	.75, 	.8),
			new HitWindow('bad', 	100, 	.9, 	.5),
			new HitWindow('shit', 	50, 	1,  	.2),
			new HitWindow('shit', 	50, 	1.1,  	0) // HORRIBLE (key mashing)
		];
		windows[0].splash = true;
		windows[2].breaksCombo = true;
		windows[3].breaksCombo = true;
		windows[4].breaksCombo = true;
		
		return windows;
	}
	public static function emiDefault() {
		var windows:Array<HitWindow> = legacyDefault();
		windows[0].threshold = .3;
		windows[1].threshold = .6;

		windows[1].healthMod = .75;
		windows[2].healthMod = .25;
		windows[3].healthMod = -.5;
		windows[4].healthMod = -2;

		var killer:HitWindow = new HitWindow('killer', 500, .06, 1);
		windows.unshift(killer);
		killer.splash = true;
		
		return windows;
	}
	public static function pbotDefault() {
		final thresholdMS:Float = 160;
		var windows:Array<HitWindow> = [
			new HitWindow('killer',	0,	12.5 / thresholdMS,	1,	2 / 1.5),
			new HitWindow('sick', 	0,	45 / thresholdMS, 	1,	1),
			new HitWindow('good', 	0,	90 / thresholdMS, 	.8,	.75 / 1.5),
			new HitWindow('bad', 	0,	135 / thresholdMS, 	.5,	0),
			new HitWindow('shit', 	0,	1, 					.2,	-1 / 1.5),
			new HitWindow('shit', 	0,	1.1, 				0,	-2)
		];
		windows[0].splash = true;
		windows[1].splash = true;
		windows[3].breaksCombo = true;
		windows[4].breaksCombo = true;
		windows[5].breaksCombo = true;
		
		return windows;
	}

	public static function judgeLegacy(hitWindows:Array<HitWindow>, hitWindow:Float, time:Float):Score {
		var win:HitWindow = hitWindows[hitWindows.length - 1];
		for (window in hitWindows) {
			if (Math.abs(time) <= window.threshold * hitWindow) {
				win = window;
				break;
			}
		}

		return {hitWindow: win, rating: win.rating, healthMod: win.healthMod, accuracyMod: win.accuracyMod, score: win.score};
	}
	public static function judgePBOT1(hitWindows:Array<HitWindow>, hitWindow:Float, time:Float):Score {
		var win:HitWindow = hitWindows[hitWindows.length - 1];
		for (window in hitWindows) {
			if (Math.abs(time) <= window.threshold * hitWindow) {
				win = window;
				break;
			}
		}

		final scoringOffset:Float = 54.99; // probably move these to Scoring
		final scoringSlope:Float = .080;
		final maxScore:Float = 500;
		final minScore:Float = 9;

		var score:Float;
		var accuracyMod:Float;
		var absTime:Float = Math.abs(time);
		if (absTime / hitWindow <= 5 / 160) {
			score = maxScore;
			accuracyMod = 1;
		} else {
			var factor:Float = 1 - (1 / (1 + Math.exp(-scoringSlope * (absTime - scoringOffset))));
			score = Math.floor(maxScore * factor + minScore);
			accuracyMod = score / maxScore;
		}

		return {hitWindow: win, rating: win.rating, healthMod: win.healthMod, accuracyMod: accuracyMod, score: score};
	}
}

class ScoreHandler {
	public var ratingCount:Map<String, Int> = [];
	public var hitWindows:Array<HitWindow> = [];
	public var system:ScoringSystem;

	public var holdScorePerSecond:Float;

	public function new(system:ScoringSystem = LEGACY) {
		this.system = system;
		this.hitWindows = switch (system) {
			case EMI:
				holdScorePerSecond = 250;
				Scoring.emiDefault();
			case PBOT1:
				holdScorePerSecond = 250;
				Scoring.pbotDefault();
			default:
				holdScorePerSecond = 0;
				Scoring.legacyDefault();
		}
	}

	public function judgeNoteHit(note:Note, time:Float):Score {
		return switch (system) {
			case EMI | WEEK7 | LEGACY:
				var score:Score = Scoring.judgeLegacy(hitWindows, note.hitWindow, time);
				// todo : fun stuff!
				score;
			case PBOT1:
				var score:Score = Scoring.judgePBOT1(hitWindows, note.hitWindow, time);
				score;
		}
	}
	public function judgeNoteMiss(note:Note):Score {
		return switch (system) {
			case EMI:
				{score: -50};
			default:
				{score: -10};
		}
	}
	public function getHitWindow(rating:String)
		return hitWindows.find((win:HitWindow) -> win.rating == rating);
	public function getRatingCount(rating:String)
		return ratingCount.get(rating) ?? 0;
	public function countRating(rating:String)
		ratingCount.set(rating, getRatingCount(rating) + 1);
}

@:structInit class Score {
	public var hitWindow:HitWindow = null;
	public var accuracyMod:Float = 0;
	public var healthMod:Float = 1;
	public var rating:String = '';
	public var score:Float = 0;
}

class HitWindow {
	public var count:Int;
	public var score:Float;
	public var rating:String;
	public var threshold:Float;
	public var healthMod:Float;
	public var accuracyMod:Float;
	public var splash:Bool = false;
	public var breaksCombo:Bool = false;
	
	public function new(rating:String, score:Float, threshold:Float, ratingMod:Float, healthMod:Float = 1) {
		this.count = 0;
		this.score = score;
		this.rating = rating;
		this.threshold = threshold;
		this.healthMod = healthMod;
		this.accuracyMod = ratingMod;
	}
}

enum abstract ScoringSystem(String) {
	var LEGACY; // rating
	var WEEK7;
	var EMI;

	var PBOT1; // timing
}