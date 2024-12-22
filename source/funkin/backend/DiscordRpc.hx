package funkin.backend;

#if hxdiscord_rpc
import hxdiscord_rpc.Discord;
import hxdiscord_rpc.Types;
import sys.thread.Thread;
#end

class DiscordRPC {
	public static var dirty:Bool = false;
	public static var initialized:Bool = false;
	public static var clientID(default, set):String = '1285413579893506118';
	
	#if hxdiscord_rpc
	public static var presence:DiscordRichPresence = DiscordRichPresence.create();
	
	public static function prepare() {
		initialize();
		lime.app.Application.current.window.onClose.add(() -> shutdown());
	}
	public static function initialize() {
		if (initialized) return;
		
		final handlers:DiscordEventHandlers = DiscordEventHandlers.create();
		handlers.ready = cpp.Function.fromStaticFunction(onReady);
		handlers.disconnected = cpp.Function.fromStaticFunction(onDisconnected);
		handlers.errored = cpp.Function.fromStaticFunction(onError);
		Discord.Initialize(clientID, cpp.RawPointer.addressOf(handlers), 1, null);
		
		Thread.create(() -> {
			while (true) {
				#if DISCORD_DISABLE_IO_THREAD
				Discord.UpdateConnection();
				#end
				Discord.RunCallbacks();
				
				Sys.sleep(2);
			}
		});
		initialized = true;
	}
	public static function refresh() {
		if (initialized) Discord.UpdatePresence(cpp.RawConstPointer.addressOf(presence));
	}
	public static function update() {
		if (dirty) {
			refresh();
			dirty = false;
		}
	}
	public static function shutdown() {
		if (initialized) {
			Discord.Shutdown();
			initialized = false;
		}
	}
	
	private static function set_clientID(newID:String) {
		if (clientID != newID) {
			clientID = newID;
			shutdown();
			initialize();
			update();
		}
		return newID;
	}
	
	private static function onReady(request:cpp.RawConstPointer<DiscordUser>):Void {
		final username:String = request[0].username;
		final globalName:String = request[0].username;
		final discriminator:Int = Std.parseInt(request[0].discriminator);
		
		if (discriminator != 0)
			Log.info('Discord: connected to user $username#$discriminator ($globalName)');
		else
			Log.info('Discord: connected to user @$username ($globalName)');
		
		presence.largeImageKey = 'banner';
		update();
	}
	private static function onDisconnected(errorCode:Int, message:cpp.ConstCharStar):Void {
		Log.error('Discord: disconnected ($errorCode:$message)');
	}
	private static function onError(errorCode:Int, message:cpp.ConstCharStar):Void {
		Log.error('Discord: $errorCode:$message');
	}
	#else
	public static var presence:Dynamic = {};
	
	public static function prepare() {}
	public static function update() {}
	public static function refresh() {}
	public static function shutdown() {}
	public static function initialize() {}
	private static function set_clientID(newID:String) return newID;
	#end
}