import SwiftUI

struct UnderDevelopmentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image("UnderDevelopment")
                .resizable()
                .scaledToFit()
                .frame(width: 400, height: 300)
                .foregroundColor(.accentColor)
            
            Text("Under Development")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text("This feature is currently being built.\nCheck back soon!")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct UnderDevelopmentView_Previews: PreviewProvider {
    static var previews: some View {
        UnderDevelopmentView()
    }
}
