// Visor HUD sidebar for cmux: shield meter, motion tracker (one blip per workspace) and waypoints.
// Blips: gold = current workspace, red = needs attention / unread, cyan = everything else.
let hud = "#3FD0FF"
let hudDim = "#16384C"
let gold = "#F5B841"
let enemy = "#E5484D"
let green = "#7FB548"

// Blip positions on the tracker (no trig in the interpreter, so a fixed ring of spots).
let spots = [[0, -30], [26, -15], [26, 15], [0, 30], [-26, 15], [-26, -15], [0, -14], [12, 7], [-12, 7], [0, 0]]

let hostile = workspaces.filter { $0.unread > 0 || $0.status == "needs-attention" }.count
let total = max(workspaceCount, 1)
let shield = 12 - (hostile * 12) / total

func blipColor(_ w: Any) -> String {
    return w.selected ? gold : ((w.unread > 0 || w.status == "needs-attention") ? enemy : hud)
}

VStack(alignment: .leading, spacing: 10) {
    HStack {
        Text("VISOR // HUD").font(.system(size: 12, design: .monospaced)).bold().foregroundColor(hud)
        Spacer()
        Text(clock.time).font(.system(size: 11, design: .monospaced)).foregroundColor(gold)
    }

    VStack(alignment: .leading, spacing: 4) {
        Text("SHIELDS").font(.system(size: 9, design: .monospaced)).foregroundColor(hud).opacity(0.7)
        HStack(spacing: 2) {
            for i in 0..<12 {
                Rectangle()
                    .fill(i < shield ? (shield <= 3 ? enemy : hud) : hudDim)
                    .frame(height: 7)
                    .shadow(color: i < shield ? hud : "#00000000", radius: 3, x: 0, y: 0)
            }
        }
    }

    HStack {
        Spacer()
        ZStack {
            Circle().fill("#3FD0FF14").frame(width: 92, height: 92)
            Circle().stroke(hud, lineWidth: 1).frame(width: 92, height: 92).opacity(0.7)
            Circle().stroke(hud, lineWidth: 1).frame(width: 60, height: 60).opacity(0.35)
            Circle().stroke(hud, lineWidth: 1).frame(width: 28, height: 28).opacity(0.25)
            Rectangle().fill(hud).frame(width: 92, height: 1).opacity(0.2)
            Rectangle().fill(hud).frame(width: 1, height: 92).opacity(0.2)
            Circle().trim(from: 0.0, to: 0.12).stroke(hud, lineWidth: 46).frame(width: 46, height: 46)
                .rotationEffect(.degrees(Double(clock.second * 6)))
                .opacity(0.25)
            ForEach(Array(workspaces.prefix(10).enumerated()), id: \.offset) { i, w in
                Circle().fill(blipColor(w)).frame(width: 7, height: 7)
                    .shadow(color: blipColor(w), radius: 4, x: 0, y: 0)
                    .offset(x: spots[i][0], y: spots[i][1])
            }
        }
        .frame(width: 96, height: 96)
        Spacer()
    }

    HStack {
        Text("CONTACTS \(hostile)").font(.system(size: 10, design: .monospaced))
            .foregroundColor(hostile > 0 ? enemy : green)
        Spacer()
        Text("WP \(workspaceCount)").font(.system(size: 10, design: .monospaced)).foregroundColor(hud)
    }

    Rectangle().fill(hud).frame(height: 1).opacity(0.4)
    Text("WAYPOINTS").font(.system(size: 9, design: .monospaced)).foregroundColor(hud).opacity(0.7)

    ScrollView {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(workspaces.prefix(30)) { w in
                Button(action: { cmux("workspace.select", workspace_id: w.id) }) {
                    HStack(spacing: 6) {
                        Text(w.selected ? "◆" : "◇").font(.system(size: 10, design: .monospaced))
                            .foregroundColor(blipColor(w))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.title.uppercased()).font(.system(size: 11, design: .monospaced))
                                .foregroundColor(w.selected ? gold : "#C8E9F5")
                                .lineLimit(1)
                            if let b = w.branch {
                                Text("\(b)\(w.dirty == true ? " *" : "")").font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(hud).opacity(0.6).lineLimit(1)
                            }
                        }
                        Spacer()
                        if w.unread > 0 {
                            Text("\(w.unread)").font(.system(size: 9, design: .monospaced)).bold()
                                .foregroundColor("#050A12")
                                .padding(.horizontal, 5)
                                .background(enemy)
                                .cornerRadius(3)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(w.selected ? "#3FD0FF1F" : "#00000000")
                    .overlay(alignment: .leading) {
                        Rectangle().fill(w.selected ? gold : "#00000000").frame(width: 2)
                    }
                }
            }
        }
    }
}
.padding(12)
.background("#050A12")
