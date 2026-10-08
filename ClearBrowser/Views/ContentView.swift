 
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        HomeView(viewModel: viewModel)
    }
}
