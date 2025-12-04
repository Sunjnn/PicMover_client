//
//  ContentView.swift
//  PicMover_client
//
//  Created by sunjnn on 2025/10/20.
//

import SwiftUI

let PORT: Int = 54321

struct ContentView: View {
    @State private var _serverMetas: [ServerMeta] = []
    @State private var _scanStatus: String = "Scanning LAN..."

    var body: some View {
        NavigationView {
            VStack {
                Text("PicMover server in LAN")
                    .font(.headline)
                    .padding(.top)

                Text(_scanStatus)
                    .padding()

                List(_serverMetas, id: \.host) { meta in
                    NavigationLink(destination: ServerDetailView(meta: meta)) {
                        Text("Server Name: \(meta.name)\nIP: \(meta.host)")
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .onAppear {
                scanLANForServer()
            }
        }
    }

    func scanLANForServer() {
        let possibleIPs = ["127.0.0.1"]
        //        serverFoundIPs = possibleIPs

        let group = DispatchGroup()
        var found = [ServerMeta]()

        for ip in possibleIPs {
            group.enter()
            let urlString = "http://\(ip):\(PORT)/ping"
            guard let url = URL(string: urlString) else {
                group.leave()
                continue
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 1.5

            URLSession.shared.dataTask(with: request) { data, response, _ in
                if let httpResponse = response as? HTTPURLResponse,
                    (200..<400).contains(httpResponse.statusCode)
                {

                    guard let data = data else {
                        return
                    }

                    var jsonObject: Any
                    do {
                        jsonObject = try JSONSerialization.jsonObject(
                            with: data
                        )
                    } catch {
                        return
                    }

                    guard let dict = jsonObject as? [String: Any] else {
                        return
                    }

                    guard let name = dict["Name"] as? String else {
                        print("No 'Name' in \(dict)")
                        return
                    }

                    DispatchQueue.main.async {
                        let meta = ServerMeta(host: ip, name: name)
                        found.append(meta)
                    }
                }
                group.leave()
            }.resume()
        }

        group.notify(queue: .main) {
            if found.isEmpty {
                _scanStatus = "No PicMover server found in LAN"
            } else {
                _scanStatus = "Scan complete"
                _serverMetas = found
            }
        }
    }
}

#Preview {
    ContentView()
}
