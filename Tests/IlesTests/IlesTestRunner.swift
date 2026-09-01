import Foundation

@main
enum IlesTestRunner {
    static func main() async {
        let code = await IlesSelfTests.run()
        if code != 0 {
            exit(Int32(code))
        }
    }
}
