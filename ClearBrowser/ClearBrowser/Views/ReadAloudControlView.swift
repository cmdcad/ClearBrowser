import SwiftUI

struct ReadAloudControlView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var playbackSpeed: Float = 1.0
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Play/Pause Button
                Button(action: {
                    if viewModel.isReadAloudPlaying {
                        viewModel.pauseReadAloud()
                    } else if viewModel.isReadAloudAvailable {
                        viewModel.resumeReadAloud()
                    }
                }) {
                    Image(systemName: viewModel.isReadAloudPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                .disabled(!viewModel.isReadAloudAvailable && !viewModel.isReadAloudPlaying)
                
                // Stop Button
                Button(action: {
                    viewModel.stopReadAloud()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                }
                .disabled(!viewModel.isReadAloudAvailable && !viewModel.isReadAloudPlaying)
                
                Spacer()
                
                // Speed Control
                HStack(spacing: 8) {
                    Text("Speed:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $playbackSpeed, in: 0.5...2.0, step: 0.1)
                        .frame(width: 80)
                        .onChange(of: playbackSpeed) { newSpeed in
                            viewModel.setReadAloudSpeed(newSpeed)
                        }
                    
                    Text(String(format: "%.1f×", playbackSpeed))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 30)
                }
            }
            
            // Progress Bar
            if viewModel.isReadAloudAvailable {
                VStack(spacing: 6) {
                    ProgressView(value: viewModel.readAloudDuration > 0 ? viewModel.readAloudProgress / viewModel.readAloudDuration : 0)
                        .tint(.blue)
                    
                    HStack {
                        Text(formatTime(viewModel.readAloudProgress))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatTime(viewModel.readAloudDuration))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            
            // Error Message
            if let errorMessage = viewModel.audioVixService.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                    
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.audioVixService.errorMessage = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Loading State
            if viewModel.audioVixService.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Synthesizing audio...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct ReadAloudControlView_Previews: PreviewProvider {
    static var previews: some View {
        ReadAloudControlView(viewModel: HomeViewModel())
            .padding()
            .previewLayout(.sizeThatFits)
    }
}
