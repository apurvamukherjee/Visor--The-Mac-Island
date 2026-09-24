//  BrightnessManager.swift
//  
//
//  Created by Apurva on 08/22/24.

import AppKit

// Visor: screen brightness and the keyboard backlight were two copies of this
// class, differing only in the XPC calls and the HUD they show.
final class BrightnessManager: ObservableObject {
	enum Kind { case screen, keyboard }

	static let shared = BrightnessManager(kind: .screen)
	static let keyboard = BrightnessManager(kind: .keyboard)

	@Published private(set) var rawBrightness: Float = 0

	private let kind: Kind
	private let client = XPCHelperClient.shared

	private init(kind: Kind) {
		self.kind = kind
		refresh()
	}

	func refresh() {
		Task { @MainActor in
			if let current = await read() {
				publish(brightness: current)
			}
		}
	}

	@MainActor func setRelative(delta: Float) {
		Task { @MainActor in
			let starting = await read() ?? rawBrightness
			let target = max(0, min(1, starting + delta))
			await set(target)
			VisorViewCoordinator.shared.toggleSneakPeek(
				status: true,
				type: kind == .screen ? .brightness : .backlight,
				value: CGFloat(target)
			)
		}
	}

	func setAbsolute(value: Float) {
		Task { @MainActor in
			await set(max(0, min(1, value)))
		}
	}

	private func set(_ value: Float) async {
		if await write(value) {
			publish(brightness: value)
		} else {
			refresh()
		}
	}

	private func read() async -> Float? {
		switch kind {
		case .screen: await client.currentScreenBrightness()
		case .keyboard: await client.currentKeyboardBrightness()
		}
	}

	private func write(_ value: Float) async -> Bool {
		switch kind {
		case .screen: await client.setScreenBrightness(value)
		case .keyboard: await client.setKeyboardBrightness(value)
		}
	}

	private func publish(brightness: Float) {
		DispatchQueue.main.async {
			if self.rawBrightness != brightness {
				self.rawBrightness = brightness
			}
		}
	}
}
