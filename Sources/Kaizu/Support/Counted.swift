extension Int {
    /// "1 tab", "1,204 pages". For nouns that just take an s.
    func counted(_ noun: String) -> String {
        "\(formatted()) \(self == 1 ? noun : noun + "s")"
    }
}
