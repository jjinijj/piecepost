import SwiftUI
import UIKit

/// 앱 폴더의 썸네일 파일을 정사각형으로 보여준다. 파일이 없으면 빈 칸.
struct StampThumbnail: View {
    let url: URL
    var side: CGFloat = 56

    var body: some View {
        Group {
            if let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
