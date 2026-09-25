//
//  MusicSlotConfigurationView.swift
//  
//
//  Created by Apurva on 2025-11-17.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots
    @ObservedObject private var musicManager = MusicManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Slot configuration (fixed 5)
            slotConfigurationSection

            // Reset button
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    withAnimation {
                        musicControlSlots = MusicControlButton.defaultLayout
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            ensureSlotCapacity(MusicControlButton.maxSlotCount)
        }
    }

    private var previewSection: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<MusicControlButton.maxSlotCount, id: \.self) { index in
                    let slot = slotValue(at: index)
                    Group {
                        if slot != .none {
                            slotPreview(for: slot)
                                .frame(maxWidth: 44)
                                .onDrag {
                                    NSItemProvider(object: NSString(string: "slot:\(index)"))
                                }
                                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                    handleDrop(providers) { processDropString($0, toIndex: index) }
                                }
                        } else {
                            // empty slot: allow drops but do not allow dragging
                            slotPreview(for: slot)
                                .frame(maxWidth: 44)
                                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                                    handleDrop(providers) { processDropString($0, toIndex: index) }
                                }
                        }
                    }
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 56, height: 56)

                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.primary)
                }
                .cornerRadius(10)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) { providers in
                    handleDrop(providers, perform: clearSlot)
                }

                Text("Clear slot")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 72)
            }
        }
    }

    private var slotConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Layout Preview")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Drag items in the preview to reorder or drop from the palette")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            previewSection

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Drag a control onto a slot")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(MusicControlButton.pickerOptions, id: \.self) { control in
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(NSColor.controlBackgroundColor))
                                        .frame(width: 44, height: 44)

                                    if control != .none {
                                        Image(systemName: control.iconName)
                                            .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                                            .foregroundStyle(control == .none ? Color.secondary : Color.primary)
                                            .frame(width: 28, height: 28)
                                    }
                                }
                                .cornerRadius(8)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .onDrag {
                                    return NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
                                }
                                .onTapGesture {
                                    if let idx = musicControlSlots.firstIndex(of: .none) {
                                        updateSlot(control, at: idx)
                                    } else {
                                        withAnimation { updateSlot(control, at: 0) }
                                    }
                                }

                                Text(control.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    @ViewBuilder
    private func slotPreview(for slot: MusicControlButton) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .frame(width: 44, height: 44)

            if slot != .none {
                Image(systemName: slot.iconName)
                    .font(.system(size: slot.prefersLargeScale ? 18 : 15, weight: .medium))
                    .foregroundStyle(previewIconColor(for: slot))
                    .frame(width: 28, height: 28)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
        }
        .cornerRadius(8)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private func previewIconColor(for slot: MusicControlButton) -> Color {
        switch slot {
        case .shuffle:
            return musicManager.isShuffled ? .red : .primary
        case .repeatMode:
            return musicManager.repeatMode != .off ? .red : .primary
        case .favorite:
            return musicManager.isFavoriteTrack ? .red : .primary
        default:
            return .primary
        }
    }

    private func ensureSlotCapacity(_ target: Int) {
        guard target > musicControlSlots.count else { return }
        let missing = target - musicControlSlots.count
        musicControlSlots.append(contentsOf: Array(repeating: .none, count: missing))
    }

    private func slotValue(at index: Int) -> MusicControlButton {
        guard musicControlSlots.indices.contains(index) else { return .none }
        return musicControlSlots[index]
    }

    // Visor: slots and the trash shared this loader as two copies; each now passes its action.
    private func handleDrop(_ providers: [NSItemProvider], perform action: @escaping (String) -> Void) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSString.self) {
                // Visor: `as? String` bridges the NSString, so one branch covers both casts.
                provider.loadObject(ofClass: NSString.self) { item, error in
                    guard let raw = item as? String else { return }
                    DispatchQueue.main.async {
                        action(raw)
                    }
                }
                return true
            }
        }
        return false
    }

    private func clearSlot(_ raw: String) {
        if let from = slotIndex(raw), musicControlSlots.indices.contains(from) {
            musicControlSlots[from] = .none
        }
    }

    // Visor: one parser for the "slot:N" payload both drop targets read.
    private func slotIndex(_ raw: String) -> Int? {
        guard raw.hasPrefix("slot:"), let index = Int(raw.dropFirst(5)),
              (0..<MusicControlButton.maxSlotCount).contains(index) else { return nil }
        return index
    }

    private func processDropString(_ raw: String, toIndex: Int) {
        if let from = slotIndex(raw) {
            var slots = musicControlSlots
            if from < slots.count && toIndex < slots.count {
                slots.swapAt(from, toIndex)
                musicControlSlots = slots
            }
        } else if raw.hasPrefix("control:") {
            let val = raw.replacingOccurrences(of: "control:", with: "")
            if let control = MusicControlButton(rawValue: val) {
                // If this control already exists in another slot, clear that original slot
                var slots = musicControlSlots
                if let existing = slots.firstIndex(of: control), existing != toIndex {
                    slots[existing] = .none
                    musicControlSlots = slots
                }

                updateSlot(control, at: toIndex)
            }
        }
    }

    private func updateSlot(_ value: MusicControlButton, at index: Int) {
        var slots = musicControlSlots
        if index >= slots.count {
            slots.append(contentsOf: Array(repeating: .none, count: index - slots.count + 1))
        }
        slots[index] = value
        musicControlSlots = slots
    }
}
