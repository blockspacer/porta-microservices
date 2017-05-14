#include <fstream>
#include <sstream>

// Reads file content into 'data'
void
readFile(const std::string &filename, std::string &data)
{
    std::ifstream file(filename.c_str(), std::ios::in);

    if (file.is_open())
    {
        std::stringstream ss;
        ss << file.rdbuf();

        file.close();

        data = ss.str();
    }
}

