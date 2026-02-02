import UIKit

// BlurHash decoder implementation based on the official Wolt BlurHash Swift implementation
// https://github.com/woltapp/blurhash

extension UIImage {
    /// Creates a UIImage from a BlurHash string
    /// - Parameters:
    ///   - blurHash: The BlurHash string to decode
    ///   - size: The size of the output image. 32x32 is recommended for placeholders.
    ///   - punch: A value to adjust the contrast (1 = normal, <1 = less contrast, >1 = more contrast)
    public convenience init?(blurHash: String, size: CGSize, punch: Float = 1) {
        guard blurHash.count >= 6 else { return nil }

        let sizeFlag = String(blurHash[blurHash.startIndex]).decodeBase83()
        let numY = (sizeFlag / 9) + 1
        let numX = (sizeFlag % 9) + 1

        let quantisedMaximumValue = String(blurHash[blurHash.index(blurHash.startIndex, offsetBy: 1)]).decodeBase83()
        let maximumValue = Float(quantisedMaximumValue + 1) / 166

        guard blurHash.count == 4 + 2 * numX * numY else { return nil }

        let colours: [(Float, Float, Float)] = (0 ..< numX * numY).map { i in
            if i == 0 {
                let startIndex = blurHash.index(blurHash.startIndex, offsetBy: 2)
                let endIndex = blurHash.index(blurHash.startIndex, offsetBy: 6)
                let value = String(blurHash[startIndex..<endIndex]).decodeBase83()
                return BlurHashDecoder.decodeDC(value)
            } else {
                let startIndex = blurHash.index(blurHash.startIndex, offsetBy: 4 + i * 2)
                let endIndex = blurHash.index(blurHash.startIndex, offsetBy: 4 + i * 2 + 2)
                let value = String(blurHash[startIndex..<endIndex]).decodeBase83()
                return BlurHashDecoder.decodeAC(value, maximumValue: maximumValue * punch)
            }
        }

        let width = Int(size.width)
        let height = Int(size.height)
        let bytesPerRow = width * 3
        guard let data = CFDataCreateMutable(kCFAllocatorDefault, bytesPerRow * height) else { return nil }
        CFDataSetLength(data, bytesPerRow * height)
        guard let pixels = CFDataGetMutableBytePtr(data) else { return nil }

        for y in 0 ..< height {
            for x in 0 ..< width {
                var r: Float = 0
                var g: Float = 0
                var b: Float = 0

                for j in 0 ..< numY {
                    for i in 0 ..< numX {
                        let basis = cos(Float.pi * Float(x) * Float(i) / Float(width)) * cos(Float.pi * Float(y) * Float(j) / Float(height))
                        let colour = colours[i + j * numX]
                        r += colour.0 * basis
                        g += colour.1 * basis
                        b += colour.2 * basis
                    }
                }

                let intR = UInt8(BlurHashDecoder.linearTosRGB(r))
                let intG = UInt8(BlurHashDecoder.linearTosRGB(g))
                let intB = UInt8(BlurHashDecoder.linearTosRGB(b))

                pixels[3 * x + 0 + y * bytesPerRow] = intR
                pixels[3 * x + 1 + y * bytesPerRow] = intG
                pixels[3 * x + 2 + y * bytesPerRow] = intB
            }
        }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let provider = CGDataProvider(data: data) else { return nil }
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 24,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }

        self.init(cgImage: cgImage)
    }
}

/// BlurHash decoder helper functions
enum BlurHashDecoder {
    static func decodeDC(_ value: Int) -> (Float, Float, Float) {
        let intR = value >> 16
        let intG = (value >> 8) & 255
        let intB = value & 255
        return (sRGBToLinear(intR), sRGBToLinear(intG), sRGBToLinear(intB))
    }

    static func decodeAC(_ value: Int, maximumValue: Float) -> (Float, Float, Float) {
        let quantR = value / (19 * 19)
        let quantG = (value / 19) % 19
        let quantB = value % 19

        let rgb = (
            signPow((Float(quantR) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantG) - 9) / 9, 2) * maximumValue,
            signPow((Float(quantB) - 9) / 9, 2) * maximumValue
        )

        return rgb
    }

    static func signPow(_ value: Float, _ exp: Float) -> Float {
        return copysign(pow(abs(value), exp), value)
    }

    static func linearTosRGB(_ value: Float) -> Int {
        let v = max(0, min(1, value))
        if v <= 0.0031308 { return Int(v * 12.92 * 255 + 0.5) }
        else { return Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5) }
    }

    static func sRGBToLinear<Type: BinaryInteger>(_ value: Type) -> Float {
        let v = Float(Int64(value)) / 255
        if v <= 0.04045 { return v / 12.92 }
        else { return pow((v + 0.055) / 1.055, 2.4) }
    }
}

// MARK: - Base83 Decoding

private let blurHashCharacters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

private let blurHashDecodeCharacters: [Character: Int] = {
    var dict: [Character: Int] = [:]
    for (index, character) in blurHashCharacters.enumerated() {
        dict[character] = index
    }
    return dict
}()

extension String {
    func decodeBase83() -> Int {
        var value: Int = 0
        for character in self {
            if let digit = blurHashDecodeCharacters[character] {
                value = value * 83 + digit
            }
        }
        return value
    }
}

/// Converts a BlurHash string to a UIImage
/// - Parameters:
///   - blurHash: The BlurHash string to decode
///   - width: The width of the output image (default: 32)
///   - height: The height of the output image (default: 32)
///   - punch: A value to adjust the contrast (default: 1)
/// - Returns: A UIImage representing the BlurHash
func blurHashToImage(blurHash: String, width: Int = 32, height: Int = 32, punch: Float = 1) -> UIImage {
    guard let image = UIImage(blurHash: blurHash, size: CGSize(width: width, height: height), punch: punch) else {
        // Return a 1x1 transparent image as fallback
        UIGraphicsBeginImageContext(CGSize(width: 1, height: 1))
        let fallback = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return fallback
    }
    return image
}
