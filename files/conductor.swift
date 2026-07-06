func statusColor(_ label: String) -> String {
    return label == "RUNNING" ? "#60a5fa" : (label == "WAITING" ? "#fb923c" : "#4ade80")
}

// Self-drawn spinner (clock-driven, keeps spinning while unfocused)
func spinner(_ sec: Int) -> String {
    let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    return frames[sec % 10]
}

VStack(alignment: .leading, spacing: 0) {
    HStack {
        Text("Workspaces").font(.title3).bold()
        Spacer()
    }.padding(6)
    Spacer().frame(height: 8)
    ScrollView {
        VStack(alignment: .leading, spacing: 2) {
            Reorderable(workspaces, move: "workspace.reorder") { w in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .imageScale(.small)
                            .foregroundColor(w.selected ? "#4C8DFF" : .secondary)
                        Text(w.title)
                            .font(.callout).bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Text("\(w.tabCount)")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .frame(width: w.tabCount > 9 ? 20 : 14, height: 14)
                            .background {
                                Capsule().fill("#1b2932")
                            }
                            .fixedSize()
                        if w.pinned {
                            Image(systemName: "pin.fill")
                                .imageScale(.small)
                                .foregroundColor("#fbbf24")
                                .rotationEffect(.degrees(45))
                        }
                        Spacer(minLength: 3)
                        if let p = w.progress {
                            Text("\(p.label)".hasPrefix("RUNNING") ? "RUNNING" : ("\(p.label)".hasPrefix("WAITING") ? "WAITING" : "READY"))
                                .font(.system(size: 9)).bold()
                                .foregroundColor(statusColor("\(p.label)".hasPrefix("RUNNING") ? "RUNNING" : ("\(p.label)".hasPrefix("WAITING") ? "WAITING" : "READY")))
                                .padding(2)
                                .background("#0a141b")
                                .cornerRadius(7)
                                .fixedSize()
                        }
                        if w.index < 9 {
                            Text("⌘\(w.index + 1)")
                                .font(.system(size: 8))
                                .foregroundColor("#5a6b78")
                                .fixedSize()
                        }
                    }
                    .padding(4)
                    .onTapGesture { cmux("workspace.select", workspace_id: w.id) }
                    .contextMenu {
                        Button("Rename…") { cmux("notification.create_for_caller", title: "cmux-rename", body: w.id) }
                        Button("Move to Top") { cmux("workspace.action", action: "move_top", workspace_id: w.id) }
                        Button("Move Up") { cmux("workspace.action", action: "move_up", workspace_id: w.id) }
                        Button("Move Down") { cmux("workspace.action", action: "move_down", workspace_id: w.id) }
                        Button(w.pinned ? "Unpin" : "Pin") { cmux("workspace.action", action: w.pinned ? "unpin" : "pin", workspace_id: w.id) }
                        Button("Mark as Read") { cmux("workspace.action", action: "mark_read", workspace_id: w.id) }
                        Button("New Tab") { cmux("surface.create", workspace_id: w.id, focus: true) }
                        Button("Close Workspace") { cmux("workspace.close", workspace_id: w.id) }
                    }
                    ForEach(w.tabs.prefix(12)) { t in
                        HStack(spacing: 6) {
                            Spacer().frame(width: 12)
                            if let p = w.progress {
                                if p.label.contains("run:\(t.id)") {
                                    Text(["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"][clock.second % 10])
                                        .font(.system(size: 12)).bold()
                                        .foregroundColor("#60a5fa")
                                        .frame(width: 16)
                                } else {
                                    Image(systemName: "terminal")
                                        .imageScale(.small)
                                        .foregroundColor(t.focused && w.selected ? "#4C8DFF" : .secondary)
                                }
                            } else {
                                Image(systemName: "terminal")
                                    .imageScale(.small)
                                    .foregroundColor(t.focused && w.selected ? "#4C8DFF" : .secondary)
                            }
                            Text(t.title)
                                .font(.caption)
                                .foregroundColor(t.focused && w.selected ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            if let p = w.progress {
                                if p.label.contains("done:\(t.id)") {
                                    Circle().fill("#E5484D").frame(width: 7, height: 7).fixedSize()
                                }
                            }
                        }
                        .padding(6)
                        .background(t.focused && w.selected ? "#17293a" : "#141f29")
                        .cornerRadius(7)
                        .overlay {
                            t.focused && w.selected
                                ? AnyView(RoundedRectangle(cornerRadius: 7).stroke("#3b82f6", lineWidth: 1))
                                : AnyView(EmptyView())
                        }
                        .onTapGesture {
                            cmux("workspace.select", workspace_id: w.id)
                            cmux("surface.focus", surface_id: t.id)
                            cmux("notification.create_for_caller", title: "cmux-seen", body: t.id)
                        }
                    }
                    if w.tabCount > 12 {
                        Text("+ \(w.tabCount - 12) more")
                            .font(.caption2).foregroundColor(.secondary)
                            .padding(4)
                    }
                }
                .padding(2)
            }
        }
    }
}
