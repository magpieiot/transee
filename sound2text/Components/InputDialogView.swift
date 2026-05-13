//
//  InputDialogView.swift
//  sound2text
//
//  Created by gavanwang on 8/25/25.
//

import SwiftUI
/// A generic macOS-style dialog with an input field.
/// Can be used as a custom sheet or overlay.
struct InputDialogView: View {
    var title: String
    var message: String? = nil
    var placeholder: String = ""
    @Binding var text: String
    var confirmTitle: String = "OK"
    var cancelTitle: String = "Cancel"
    var onConfirm: () -> Void
    var onCancel: () -> Void
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                if let message = message {
                    Text(message)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            // Input Field
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    onConfirm()
                }
            
            // Buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button(action: onCancel) {
                    Text(cancelTitle)
                        .frame(minWidth: 60)
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: onConfirm) {
                    Text(confirmTitle)
                        .frame(minWidth: 60)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        )
        // Add a subtle border for better contrast on dark backgrounds
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - View Extension for Easy Usage

extension View {
    /// Presents a custom input alert.
    /// - Parameters:
    ///   - isPresented: Binding to control visibility.
    ///   - title: Dialog title.
    ///   - message: Optional dialog message.
    ///   - text: Binding to the input text.
    ///   - placeholder: Placeholder text.
    ///   - confirmTitle: Title for the confirm button.
    ///   - cancelTitle: Title for the cancel button.
    ///   - onConfirm: Action to perform on confirmation.
    ///   - onCancel: Action to perform on cancellation (optional, defaults to closing).
    func inputDialog(
        isPresented: Binding<Bool>,
        title: String,
        message: String? = nil,
        text: Binding<String>,
        placeholder: String = "",
        confirmTitle: String = "OK",
        cancelTitle: String = "Cancel",
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            self
                .disabled(isPresented.wrappedValue) // Disable underlying view interaction
                .blur(radius: isPresented.wrappedValue ? 2 : 0) // Optional: blur background
            
            if isPresented.wrappedValue {
                Color.black.opacity(0.15) // Dimmed background
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Optional: Tap outside to dismiss
                         // isPresented.wrappedValue = false
                         // onCancel?()
                    }
                
                InputDialogView(
                    title: title,
                    message: message,
                    placeholder: placeholder,
                    text: text,
                    confirmTitle: confirmTitle,
                    cancelTitle: cancelTitle,
                    onConfirm: {
                        onConfirm()
                        isPresented.wrappedValue = false
                    },
                    onCancel: {
                        if let onCancel = onCancel {
                            onCancel()
                        }
                        isPresented.wrappedValue = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPresented.wrappedValue)
    }

    func errorAlert(
        isPresented: Binding<Bool>,
        title: String = "Error",
        message: String,
        iconSystemName: String = "exclamationmark.triangle.fill",
        iconColor: Color = .red,
        okTitle: String = "OK",
        onOK: (() -> Void)? = nil
    ) -> some View {
        ZStack {
            self
                .disabled(isPresented.wrappedValue)
                .blur(radius: isPresented.wrappedValue ? 2 : 0)

            if isPresented.wrappedValue {
                Color.black.opacity(0.15)
                    .edgesIgnoringSafeArea(.all)

                StandardErrorAlertView(
                    title: title,
                    message: message,
                    iconSystemName: iconSystemName,
                    iconColor: iconColor,
                    okTitle: okTitle,
                    onOK: {
                        onOK?()
                        isPresented.wrappedValue = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isPresented.wrappedValue)
    }
}

private struct StandardErrorAlertView: View {
    let title: String
    let message: String
    let iconSystemName: String
    let iconColor: Color
    let okTitle: String
    let onOK: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: iconSystemName)
                .foregroundColor(iconColor)
                .font(.system(size: 54, weight: .semibold))
                .padding(.top, 4)

            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            Button(action: onOK) {
                Text(okTitle)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .padding(.top, 8)
        }
        .padding(22)
        .frame(width: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .onExitCommand(perform: onOK)
    }
}

// MARK: - Preview

struct InputDialogView_Previews: PreviewProvider {
    static var previews: some View {
        StateWrapper()
    }
    
    struct StateWrapper: View {
        @State private var isPresented = false
        @State private var text = ""
        @State private var isErrorPresented = false
        @State private var errorMessage = ""
        
        var body: some View {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .frame(width: 500, height: 400)
                
                Button("Show Alert") {
                    errorMessage = "Network connection failed. Please check your network settings."
                    isErrorPresented = true
                }
            }
            .errorAlert(isPresented: $isErrorPresented, message: errorMessage)
        }
    }
}