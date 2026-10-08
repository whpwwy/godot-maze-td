class_name Audio
extends RefCounted
## 程序化音效：所有声音都在启动时用代码合成成 PCM（AudioStreamWAV），
## 不下载任何音频素材。播放走固定播放器池 + 限流，避免音源爆炸。

const RATE := 22050
const VOICES := 24

var _parent: Node = null
var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _bank: Dictionary = {}
var _muted: bool = false


func _init(parent: Node) -> void:
	_parent = parent
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -6.0
		parent.add_child(p)
		_players.append(p)
	_build()


func _build() -> void:
	_bank["shoot"] = _tone(940.0, 420.0, 0.055, 0.34, "square", 2.2)
	_bank["shoot2"] = _tone(380.0, 190.0, 0.09, 0.36, "square", 1.8)
	_bank["shoot3"] = _tone(1500.0, 900.0, 0.06, 0.26, "sine", 2.0)
	_bank["hit"] = _noise(0.05, 0.22, 3.0)
	_bank["boom"] = _boom(0.28, 0.45)
	_bank["build"] = _arp([520.0, 780.0], 0.055, 0.32)
	_bank["upgrade"] = _arp([520.0, 700.0, 980.0], 0.05, 0.30)
	_bank["sell"] = _arp([700.0, 420.0], 0.07, 0.28)
	_bank["deny"] = _tone(180.0, 120.0, 0.16, 0.32, "square", 1.2)
	_bank["leak"] = _tone(420.0, 90.0, 0.36, 0.42, "saw", 0.8)
	_bank["wave"] = _arp([330.0, 440.0, 550.0, 660.0], 0.075, 0.32)
	_bank["win"] = _arp([523.0, 659.0, 784.0, 1046.0, 1318.0], 0.11, 0.34)
	_bank["lose"] = _arp([392.0, 330.0, 262.0, 196.0], 0.15, 0.34)


func set_muted(m: bool) -> void:
	_muted = m
	if m:
		for p in _players:
			p.stop()


func play(name: String, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if _muted or not _bank.has(name):
		return
	# 找一个空闲播放器，找不到就轮转（限流，避免同时几百个音源）
	var chosen := -1
	for i in VOICES:
		var idx := (_next + i) % VOICES
		if not _players[idx].playing:
			chosen = idx
			break
	if chosen < 0:
		chosen = _next
	_next = (chosen + 1) % VOICES
	var p := _players[chosen]
	p.stream = _bank[name]
	p.pitch_scale = clampf(pitch, 0.4, 2.6)
	p.volume_db = -6.0 + vol_db
	p.play()


# ------------------------------------------------------------------ 合成
func _tone(f0: float, f1: float, dur: float, vol: float, wave: String, decay_pow: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var freq := lerpf(f0, f1, u)
		phase += freq / RATE
		var ph: float = phase - floorf(phase)
		var s := 0.0
		match wave:
			"square":
				s = 1.0 if ph < 0.5 else -1.0
			"saw":
				s = ph * 2.0 - 1.0
			_:
				s = sin(ph * TAU)
		var env := pow(1.0 - u, decay_pow)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _noise(dur: float, vol: float, decay_pow: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654321
	for i in n:
		var u := float(i) / float(n)
		var env := pow(1.0 - u, decay_pow)
		var s := rng.randf_range(-1.0, 1.0) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _boom(dur: float, vol: float) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13579
	var phase := 0.0
	for i in n:
		var u := float(i) / float(n)
		var env := pow(1.0 - u, 2.0)
		phase += lerpf(150.0, 45.0, u) / RATE
		var s := (sin(phase * TAU) * 0.7 + rng.randf_range(-1.0, 1.0) * 0.5) * env * vol
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _arp(freqs: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var per := int(note_dur * RATE)
	var total := per * freqs.size()
	var data := PackedByteArray()
	data.resize(total * 2)
	var phase := 0.0
	for ni in freqs.size():
		var f: float = freqs[ni]
		for i in per:
			var u := float(i) / float(per)
			phase += f / RATE
			var ph: float = phase - floorf(phase)
			var sq := 1.0 if ph < 0.5 else -1.0
			var env := pow(1.0 - u, 1.3)
			var s := (sq * 0.45 + sin(ph * TAU) * 0.55) * env * vol
			data.encode_s16((ni * per + i) * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	return _wav(data)


func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
