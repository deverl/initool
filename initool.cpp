#include <algorithm>
#include <cctype>
#include <exception>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <ranges>
#include <stdexcept>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

using std::string;
using std::string_view;

namespace fs = std::filesystem;

// --- Utility functions -----------------------------------------------------

inline std::string trim(std::string_view s) {
    auto start = s.find_first_not_of(" \t\r\n");
    auto end   = s.find_last_not_of(" \t\r\n");
    if (start == std::string_view::npos) {
        return "";
    }
    return std::string(s.substr(start, end - start + 1));
}

inline std::string to_lower(std::string_view s) {
    std::string out;
    out.reserve(s.size());
    for (unsigned char c : s) {
        out.push_back(static_cast<char>(std::tolower(c)));
    }
    return out;
}

inline bool starts_with(std::string_view s, char c) {
    return !s.empty() && s.front() == c;
}

inline bool is_section_header(std::string_view s) {
    return s.size() >= 3 && s.front() == '[' && s.back() == ']';
}

inline std::string unquote(std::string_view s) {
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"') {
        return std::string(s.substr(1, s.size() - 2));
    }
    return std::string(s);
}

inline std::string quote_if_needed(std::string_view s) {
    if (s.find_first_of(" =") != std::string_view::npos) {
        return "\"" + std::string(s) + "\"";
    }
    return std::string(s);
}

// --- INI File class -------------------------------------------------------

class IniFile {
public:
    explicit IniFile(fs::path path)
        : path_(std::move(path)) {
        load();
    }

    [[nodiscard]] std::string get(std::string_view section, std::string_view key) const {
        auto sec = to_lower(section);
        auto k   = to_lower(key);
        if (auto it = data_.find(sec); it != data_.end()) {
            if (auto jt = it->second.find(k); jt != it->second.end()) {
                return jt->second;
            }
        }
        throw std::runtime_error("Error: key not found");
    }

    void set(std::string_view section, std::string_view key, std::string_view value) {
        const std::string sec_lower = to_lower(section);
        const std::string key_lower = to_lower(key);
        const std::string val       = std::string(value);

        auto              sec_it    = section_lines_.find(sec_lower);
        if (sec_it == section_lines_.end()) {
            // Section not found → append new section and key
            if (!lines_.empty() && !trim(lines_.back()).empty()) {
                lines_.push_back("");
            }
            lines_.push_back("[" + std::string(section) + "]");
            lines_.push_back(std::string(key) + " = " + quote_if_needed(val));
        } else {
            // Section exists
            size_t section_line = sec_it->second;
            auto&  keys         = key_lines_[sec_lower];

            if (auto key_it = keys.find(key_lower); key_it != keys.end()) {
                // Update existing key
                size_t      line_no = key_it->second;
                auto        pos     = lines_[line_no].find('=');
                std::string lhs     = trim(lines_[line_no].substr(0, pos));
                lines_[line_no]     = lhs + " = " + quote_if_needed(val);
            } else {
                // Insert new key after last known key in this section
                size_t insert_at = section_line + 1;
                while (insert_at < lines_.size()) {
                    std::string t = trim(lines_[insert_at]);
                    if (starts_with(t, '[')) {
                        // Found start of next section
                        // Step back if the previous line is blank
                        if (insert_at > section_line + 1 && trim(lines_[insert_at - 1]).empty()) {
                            --insert_at;
                        }
                        break;
                    }
                    insert_at++;
                }
                lines_.insert(lines_.begin() + insert_at,
                              std::string(key) + " = " + quote_if_needed(val));
            }
        }

        write();
    }

private:
    fs::path                                                                      path_;
    std::vector<std::string>                                                      lines_;
    std::unordered_map<std::string, size_t>                                       section_lines_;
    std::unordered_map<std::string, std::unordered_map<std::string, size_t>>      key_lines_;
    std::unordered_map<std::string, std::unordered_map<std::string, std::string>> data_;

    void                                                                          load() {
        std::ifstream f(path_);
        if (!f) {
            throw std::runtime_error("Error: cannot open file " + path_.string());
        }

        std::string line;
        std::string current_section;

        for (size_t lineno = 0; std::getline(f, line); ++lineno) {
            lines_.push_back(line);
            std::string t = trim(line);

            if (t.empty() || t.starts_with(';')) {
                continue;
            }

            if (is_section_header(t)) {
                current_section                 = to_lower(trim(t.substr(1, t.size() - 2)));
                section_lines_[current_section] = lineno;
            } else if (!current_section.empty()) {
                // We’re in a section — even if the line isn’t “perfect”
                auto pos = t.find('=');
                if (pos != std::string::npos) {
                    std::string key                  = to_lower(trim(t.substr(0, pos)));
                    std::string val                  = unquote(trim(t.substr(pos + 1)));
                    data_[current_section][key]      = val;
                    key_lines_[current_section][key] = lineno;
                }
            }
        }
    }

    void write() const {
        std::ofstream f(path_, std::ios::trunc);
        if (!f) {
            throw std::runtime_error("Error: cannot write file " + path_.string());
        }

        for (auto& l : lines_) {
            f << l << '\n';
        }
    }
};

// --- Main program ----------------------------------------------------------

int main(int argc, char* argv[]) {
    try {
        if (argc < 2) {
            std::cerr << "Usage:\n"
                      << "  " << argv[0] << " --get <file> <section> <key>\n"
                      << "  " << argv[0] << " --set <file> <section> <key> <value>\n";
            return 1;
        }

        std::string command = argv[1];
        if (command == "--get") {
            if (argc != 5) {
                std::cerr << "Usage: " << argv[0] << " --get <file> <section> <key>\n";
                return 1;
            }
            IniFile ini(argv[2]);
            std::cout << ini.get(argv[3], argv[4]) << '\n';
        } else if (command == "--set") {
            if (argc != 6) {
                std::cerr << "Usage: " << argv[0] << " --set <file> <section> <key> <value>\n";
                return 1;
            }
            IniFile ini(argv[2]);
            ini.set(argv[3], argv[4], argv[5]);
            std::cout << "Updated [" << argv[3] << "] " << argv[4] << " = " << argv[5] << '\n';
        } else {
            std::cerr << "Unknown command: " << command << '\n';
            return 1;
        }

        return 0;
    } catch (const std::exception& e) {
        std::cerr << e.what() << '\n';
        return 1;
    }
}
