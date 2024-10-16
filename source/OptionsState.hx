class OptionsState extends MusicBeatState {
	public var target:FlxObject;
	public var items:FlxTypedGroup<SettingItem>;
	public var inputEnabled:Bool = true;
	public static var selection:Int = 0;
	
	override public function create() {
		super.create();
		
		playMusic('title');
		var bg:FunkinSprite = new FunkinSprite().loadTexture('menuBGMagenta');
		bg.setGraphicSize(bg.width * 1.1);
		bg.scrollFactor.set();
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);
		
		items = new FlxTypedGroup<SettingItem>();
		add(items);
		
		items.add(new SettingItem(0, 0, 'hawk one'));
		items.add(new SettingItem(40, 100, 'hawk two'));
		
		FlxG.camera.target = target = new FlxObject();
		FlxG.camera.followLerp = 9 / 60;
		select();
		FlxG.camera.snapToTarget();
		
		Main.showWatermark = true;
		
		DiscordRPC.presence.details = 'Navigating options!';
		DiscordRPC.dirty = true;
	}
	
	override public function update(elapsed:Float) {
		super.update(elapsed);
		DiscordRPC.update();
		if (!inputEnabled) return;
		
		if (FlxG.keys.justPressed.UP) select(-1);
		if (FlxG.keys.justPressed.DOWN) select(1);
		if (FlxG.keys.justPressed.ENTER) {
			var curSetting:SettingItem = items.members[selection];
			if (curSetting != null && curSetting.type == BOOLEAN) {
				curSetting.enabled = !curSetting.enabled;
			}
		}
		if (FlxG.keys.justPressed.ESCAPE) {
			FlxG.switchState(() -> new MainMenuState());
		}
	}
	
	public function select(mod:Int = 0) {
		if (items.length == 0) return;
		if (mod != 0) FlxG.sound.play(Paths.sound('scrollMenu'), .8);
		
		items.members[selection].highlight(false);
		
		selection = FlxMath.wrap(selection + mod, 0, items.length - 1);
		var selectedItem:SettingItem = items.members[selection];
		selectedItem.highlight();
		
		target.setPosition(selectedItem.x + 400, selectedItem.y + selectedItem.height * .5);
	}
}

class SettingItem extends FlxSpriteGroup {
	public var text:Alphabet;
	public var type:SettingType;
	public var checkbox:FunkinSprite = null;
	public var enabled(default, set):Bool = false;
	public function new(x:Float = 0, y:Float = 0, name:String = 'unknown', type:SettingType = BOOLEAN) {
		super(x, y);
		
		text = new Alphabet(150, 0, name);
		add(text);
		updateHitbox();
		
		this.type = type;
		switch (type) {
			case BOOLEAN:
				checkbox = new FunkinSprite(0, -70);
				checkbox.loadAtlas('options/checkbox');
				checkbox.animation.addByPrefix('select', 'checkbox select', 24, false);
				checkbox.animation.addByPrefix('unselect', 'checkbox unselect', 24, false);
				enabled = false;
				checkbox.animation.finish();
				checkbox.updateHitbox();
				add(checkbox);
			default:
		}
		highlight(false);
	}
	public function set_enabled(on:Bool) {
		if (type != BOOLEAN) return on;
		checkbox.playAnimation(on ? 'select' : 'unselect');
		return enabled = on;
	}
	public function highlight(on:Bool = true) {
		if (on) {
			checkbox.alpha = 1;
			text.alpha = 1;
			text.color = 0xffcc66;
		} else {
			checkbox.alpha = .65;
			text.alpha = .65;
			text.color = 0xffffff;
		}
	}
}

enum SettingType {
	BOOLEAN;
	NUMBER;
	STRING;
}