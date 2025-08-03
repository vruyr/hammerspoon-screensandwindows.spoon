#!/usr/bin/env swift

import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox.Events


func main() {
	guard
		let symRoot = UserDefaults.standard.persistentDomain(forName: "com.apple.symbolichotkeys"),
		let hotkeys = symRoot["AppleSymbolicHotKeys"] as? [String: Any]
	else {
		print("Could not read com.apple.symbolichotkeys")
		exit(1)
	}

	var args = Array(CommandLine.arguments.dropFirst())
	var padHotkeyNameUpto: Int = 0

	if args.isEmpty {
		args = Array(SYMBOLIC_HOTKEY_NAMES.map{ $0.0 })
		padHotkeyNameUpto = SYMBOLIC_HOTKEY_NAMES.map { $0.1.count }.max() ?? 0
	}


	for hotkeyId in args {
		if let hotkey = hotkeys[hotkeyId] {
			do {
				let (enabled, symbolicHotkey) = try decodeHotkey(hotkey)
				var symbolicHotkeyName = (
					SYMBOLIC_HOTKEY_NAMES.first(where: { $0.0 == hotkeyId })?.1 ?? hotkeyId
				)
				if padHotkeyNameUpto > 0 {
					symbolicHotkeyName = symbolicHotkeyName.padding(toLength: padHotkeyNameUpto + 1, withPad: " ", startingAt: 0)
				}
				print("\(enabled ? "ON " : "OFF") \(symbolicHotkeyName): \(symbolicHotkey)")
			} catch {
				print("Error decoding \(hotkeyId): \(error) – \(hotkey)")
			}
		} else {
			print("Hotkey ID \(hotkeyId) not found.")
		}
	}
}

let SYMBOLIC_HOTKEY_NAMES: [(String, String)] = [
	// macOS Sequoia 15.5 (24F74)
	// Experimentally determined by changing settings in System Settings
	// and diffing the output of `defaults read com.apple.symbolichotkeys`

	// Launchpad & Dock
	("52", "Turn Dock hiding on/off"),
	("160", "Show Launchpad"),

	// Display
	("53", "Decrease display brightness"),
	("54", "Increase display brightness"),

	// Mission Control
	("32", "Mission Control"),
	("163", "Show Notification Center"),
	("175", "Turn Do Not Disturn on/off"),
	("33", "Application Windows"),
	("36", "Show Desktop"),
	("222", "Turn Stage Manager on/off"),
	("79", "Move left a space"),
	("81", "Move right a space"),
	("118", "Switch to Desktop 1"),
	("119", "Switch to Desktop 2"),
	("120", "Switch to Desktop 3"),
	("121", "Switch to Desktop 4"),
	("122", "Switch to Desktop 5"),
	("123", "Switch to Desktop 6"),
	("124", "Switch to Desktop 7"),
	("190", "Quick Note"),

	// Windows: General
	("233", "Minimize"),
	("235", "Zoom"),
	("237", "Fill"),
	("238", "Center"),
	("239", "Return to Previous Size"),
	// Windows: Halves
	("240", "Tile Left Half"),
	("241", "Tile Right Half"),
	("242", "Tile Top Half"),
	("243", "Tile Bottom Half"),
	// Windows: Quarters
	("244", "Tile Top Left Quarter"),
	("245", "Tile Top Right Quarter"),
	("246", "Tile Bottom Left Quarter"),
	("247", "Tile Bottom Right Quarter"),
	// Windows: Arrange
	("248", "Arrange Left and Right"),
	("249", "Arrange Right and Left"),
	("250", "Arrange Top and Bottom"),
	("251", "Arrange Bottom and Top"),
	("256", "Arrange in Quarters"),
	// Windows: Full Screen Tile
	("257", "Full Screen Tile Left"),
	("258", "Full Screen Tile Right"),

	// Keyboard
	("13", "Change the way Tab moves focus"),
	("12", "Turn keyboard access on or off"),
	("7", "Move focus to the menu bar"),
	("8", "Move focus to the Dock"),
	("9", "Move focus to active or next window"),
	("10", "Move focus to the window toolbar"),
	("11", "Move focus to the floating window"),
	("27", "Move focus to next window"),
	("57", "Move focus to status menus"),
	("159", "Show contextual menu"),

	// Input Sources
	("60", "Select the previous input source"),
	("61", "Select next source in Input menu"),

	// Screenshots
	("28", "Save picture of screen as a file"),
	("29", "Copy picture of screen to the clipboard"),
	("30", "Save picture of selected area as a file"),
	("31", "Copy picture of selected area to the clipboard"),
	("184", "Screenshot and recording options"),

	// Presenter Overlay
	// Services: Development
	// Services: Files and Folders
	// Services: Internet
	// Services: Messaging
	// Services: Pictures
	// Services: Searching
	// Services: Text
	// Spotlight
	// Accessibility
	// App Shortcuts: All Applications
]


enum HotkeyError: Error {
	case noHotkey
	case noEnabledFlag
	case noValue
	case noParameters
	case noHotkeyType
	case invalidHotkeyType
	case invalidParameters
	case invalidKey(String)
	case invalidCodepoint(Int)
	case invalidModifiers
}

func decodeHotkey(_ hotkeyMaybe: Any?) throws -> (Bool, String) {
	// https://stackoverflow.com/questions/21878482/what-do-the-parameter-values-in-applesymbolichotkeys-plist-dict-represent
	// https://gist.github.com/aca/bb6d936325fc59b2b61090d14f9852a5

	guard let hotkey = hotkeyMaybe as? [String: Any] else {
		throw HotkeyError.noHotkey
	}
	guard let enabled = hotkey["enabled"] as? UInt else {
		throw HotkeyError.noEnabledFlag
	}
	guard let value = hotkey["value"] as? [String: Any] else {
		throw HotkeyError.noValue
	}
	guard let parameters = value["parameters"] as? [Int] else {
		throw HotkeyError.noParameters
	}
	guard let hotkeyType = value["type"] as? String else {
		throw HotkeyError.noHotkeyType
	}
	guard hotkeyType == "standard" else {
		throw HotkeyError.invalidHotkeyType
	}
	guard parameters.count == 3 else {
		throw HotkeyError.invalidParameters
	}
	let (asciiCode, keyCode, modifiersRaw) = (
		parameters[0],
		parameters[1],
		parameters[2]
	)

	return (
		(enabled == 1),
		(try decodeHotkey(asciiCode: asciiCode, keyCode: keyCode, modifiers: UInt64(modifiersRaw)))
	)
}

func decodeHotkey(asciiCode: Int, keyCode: Int, modifiers: UInt64) throws -> String {
	guard (asciiCode != 0xFFFF) || (keyCode != 0) else {
		throw HotkeyError.invalidKey("asciiCode: 0xFFFF, keyCode: 0")
	}
	if (asciiCode != 0xFFFF) && (keyCode != 0) {
		let name1 = try codepointToName(asciiCode)
		let name2 = keyCodeToName(keyCode)
		switch(name1, name2) {
		case (" ", "Space"):
			break
		default:
			guard name1.lowercased() == name2.lowercased() else {
				throw HotkeyError.invalidKey("asciiCode: \(name1), keyCode: \(name2)")
			}
		}
	}

	let modifierFlags = CGEventFlags(rawValue: modifiers)
	var result: [String] = [
		modifierFlags.contains(.maskControl)      ? "Control"   : nil, // 0x040000
		modifierFlags.contains(.maskAlternate)    ? "Option"    : nil, // 0x080000
		modifierFlags.contains(.maskShift)        ? "Shift"     : nil, // 0x020000
		modifierFlags.contains(.maskCommand)      ? "Command"   : nil, // 0x100000

		// Caps Lock is not a modifier in the sense of a key combination
		// modifierFlags.contains(.maskAlphaShift)   ? "Caps Lock" : nil, // 0x010000

		// Classifications Bits
		// modifierFlags.contains(.maskSecondaryFn)  ? "Fn"        : nil, // 0x800000
		// modifierFlags.contains(.maskHelp)         ? "Help"      : nil, // 0x400000
		// modifierFlags.contains(.maskNumericPad)   ? "NumPad"    : nil, // 0x200000
		// modifierFlags.contains(.maskNonCoalesced) ? "NoMerge"   : nil, // 0x000100
	].compactMap { $0 }

	var keyName: String

	if keyCode != 0 {
		keyName = keyCodeToName(keyCode)
	} else {
		keyName = try codepointToName(asciiCode)
	}

	result.append(keyName)

	// print(String(format: "0x%6lX ", modifiers), terminator: "")
	return result.joined(separator: "-")
}


func codepointToName(_ codepoint: Int) throws -> String {
	guard let scalar = UnicodeScalar(codepoint) else {
		throw HotkeyError.invalidCodepoint(codepoint)
	}
	return String(scalar)
}


/// Returns a human-readable name for a macOS virtual key code.
func keyCodeToName(_ keyCode: Int) -> String {
	switch keyCode {
	// Letters
	case kVK_ANSI_A:       return "A"
	case kVK_ANSI_S:       return "S"
	case kVK_ANSI_D:       return "D"
	case kVK_ANSI_F:       return "F"
	case kVK_ANSI_H:       return "H"
	case kVK_ANSI_G:       return "G"
	case kVK_ANSI_Z:       return "Z"
	case kVK_ANSI_X:       return "X"
	case kVK_ANSI_C:       return "C"
	case kVK_ANSI_V:       return "V"
	case kVK_ANSI_B:       return "B"
	case kVK_ANSI_Q:       return "Q"
	case kVK_ANSI_W:       return "W"
	case kVK_ANSI_E:       return "E"
	case kVK_ANSI_R:       return "R"
	case kVK_ANSI_Y:       return "Y"
	case kVK_ANSI_T:       return "T"
	case kVK_ANSI_1:       return "1"
	case kVK_ANSI_2:       return "2"
	case kVK_ANSI_3:       return "3"
	case kVK_ANSI_4:       return "4"
	case kVK_ANSI_6:       return "6"
	case kVK_ANSI_5:       return "5"
	case kVK_ANSI_Equal:   return "="
	case kVK_ANSI_9:       return "9"
	case kVK_ANSI_7:       return "7"
	case kVK_ANSI_Minus:   return "-"
	case kVK_ANSI_8:       return "8"
	case kVK_ANSI_0:       return "0"
	case kVK_ANSI_RightBracket: return "]"
	case kVK_ANSI_O:       return "O"
	case kVK_ANSI_U:       return "U"
	case kVK_ANSI_LeftBracket:  return "["
	case kVK_ANSI_I:       return "I"
	case kVK_ANSI_P:       return "P"
	case kVK_ANSI_L:       return "L"
	case kVK_ANSI_J:       return "J"
	case kVK_ANSI_Quote:   return "'"
	case kVK_ANSI_K:       return "K"
	case kVK_ANSI_Semicolon: return ";"
	case kVK_ANSI_Backslash: return "\\"
	case kVK_ANSI_Comma:   return ","
	case kVK_ANSI_Slash:   return "/"
	case kVK_ANSI_N:       return "N"
	case kVK_ANSI_M:       return "M"
	case kVK_ANSI_Period:  return "."
	case kVK_ANSI_Grave:   return "`"

	// Control keys
	case kVK_Return:       return "Return"
	case kVK_Tab:          return "Tab"
	case kVK_Space:        return "Space"
	case kVK_Delete:       return "Delete"
	case kVK_Escape:       return "Escape"
	case kVK_Command:      return "Command"
	case kVK_Shift:        return "Shift"
	case kVK_CapsLock:     return "Caps Lock"
	case kVK_Option:       return "Option"
	case kVK_Control:      return "Control"

	// Arrow keys
	case kVK_LeftArrow:    return "Left"
	case kVK_RightArrow:   return "Right"
	case kVK_DownArrow:    return "Down"
	case kVK_UpArrow:      return "Up"

	// Function keys
	case kVK_F1:           return "F1"
	case kVK_F2:           return "F2"
	case kVK_F3:           return "F3"
	case kVK_F4:           return "F4"
	case kVK_F5:           return "F5"
	case kVK_F6:           return "F6"
	case kVK_F7:           return "F7"
	case kVK_F8:           return "F8"
	case kVK_F9:           return "F9"
	case kVK_F10:          return "F10"
	case kVK_F11:          return "F11"
	case kVK_F12:          return "F12"

	// https://eastmanreference.com/complete-list-of-applescript-key-codes
	case 105: return "F13"
	case 107: return "F14"
	case 113: return "F15"
	case 106: return "F16"
	case  64: return "F17"
	case  79: return "F18"
	case  80: return "F19"
	case  90: return "F20"

	// Media keys (where available)
	case Int(0x7E):     return "Volume Up"
	case Int(0x7F):     return "Volume Down"
	case Int(0x80):     return "Mute"

	// Empirically determined keys
	case Int(0xFFFF): return "(none)"

	default:
		return "KeyCode(\(keyCode))"
	}
}


main()
