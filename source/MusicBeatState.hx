package;

import flixel.util.FlxSignal.FlxTypedSignal;

class MusicBeatState implements IMusicBeat extends FlxState {
	var time:Float = -1;
	public var realElapsed:Float;

	public var curBar:Int = -1;
	public var curBeat:Int = -1;
	public var curStep:Int = -1;

	public var paused:Bool = false;
	public var conductorInUse:Conductor = Conductor.global;

	public var stepHit:FlxTypedSignal<Int->Void> = new FlxTypedSignal<Int->Void>();
	public var beatHit:FlxTypedSignal<Int->Void> = new FlxTypedSignal<Int->Void>();
	public var barHit:FlxTypedSignal<Int->Void> = new FlxTypedSignal<Int->Void>();
	
	public var hscripts:HScripts = new HScripts();
	
	override function create() {
		Main.soundTray.reloadSoundtrayGraphics();
		Paths.trackedAssets.resize(0);
		super.create();
	}
	override public function destroy() {
		hscripts.destroyAll();
		super.destroy();
	}

	public function sortZIndex() {
		sort(Util.sortZIndex, FlxSort.ASCENDING);
	}
	public function insertZIndex(obj:FunkinSprite) {
		if (members.contains(obj)) remove(obj);
		var low:Float = Math.POSITIVE_INFINITY;
		for (pos => mem in members) {
			low = Math.min(mem.zIndex, low);
			if (obj.zIndex < mem.zIndex) {
				insert(pos, obj);
				return obj;
			}
		}
		if (obj.zIndex < low) {
			insert(0, obj);
		} else {
			add(obj);
		}
		return obj;
	}
	
	public function resetMusic() {
		curBar = -1;
		curBeat = -1;
		curStep = -1;
		conductorInUse.songPosition = 0;
	}
	public function resetState() {
		FlxG.resetState();
	}

	public function getRealElapsed() {
		var curTime:Float = haxe.Timer.stamp();
		if (time < 0) time = curTime;
		var realTime:Float = Math.min(curTime - time, FlxG.maxElapsed);
		realElapsed = realTime;
		time = curTime;
		return realElapsed;
	}
	override function update(elapsed:Float) {
		if (FlxG.keys.justPressed.F5) resetState();
		
		if (paused) return;
		
		updateConductor(elapsed);
		super.update(elapsed);
	}
	
	public function updateConductor(elapsed:Float = 0) {
		var prevStep:Int = curStep;
		var prevBeat:Int = curBeat;
		var prevBar:Int = curBar;

		conductorInUse.update(elapsed * 1000);
		
		curStep = Math.floor(conductorInUse.metronome.step);
		curBeat = Math.floor(conductorInUse.metronome.beat);
		curBar = Math.floor(conductorInUse.metronome.bar);
		
		if (prevBar != curBar) barHit.dispatch(curBar);
		if (prevBeat != curBeat) beatHit.dispatch(curBeat);
		if (prevStep != curStep) stepHit.dispatch(curStep);
	}
	
	public function playMusic(mus:String) {
		MusicHandler.playMusic(mus);
		MusicHandler.applyMeta(conductorInUse);
	}
	
	public static function getCurrentConductor():Conductor {
		if (Std.isOfType(FlxG.state, IMusicBeat))
			return cast(FlxG.state, IMusicBeat).conductorInUse;
		return Conductor.global;
	}
}