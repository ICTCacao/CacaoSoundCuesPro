import CoreMIDI
import Foundation
// 画面写真用の仮想 MIDI 機器（入力「MIDI Controller」、出力「Lighting Console」）。止めるまで生きている
var client = MIDIClientRef()
MIDIClientCreateWithBlock("Screenshot" as CFString, &client) { _ in }
var src = MIDIEndpointRef()
MIDISourceCreateWithProtocol(client, "MIDI Controller" as CFString, ._1_0, &src)
var dst = MIDIEndpointRef()
MIDIDestinationCreateWithProtocol(client, "Lighting Console" as CFString, ._1_0, &dst) { _, _ in }
print("virtual MIDI up")
fflush(stdout)
RunLoop.main.run()
