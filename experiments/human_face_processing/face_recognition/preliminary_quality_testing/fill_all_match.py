import csv

MATCHES_FILENAME = "matchpairsDevTrain.csv"
CLEAR_FILENAME = "all_clear_buffalo_l.csv"
OUTPUT_FILENAME = "all_match_buffalo_l.csv"

def get_clear():
    result = {}
    with open(CLEAR_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            imagenum = int(row["imagenum"])
            if result.get(name) is None:
                result[name] = {}
            result[name][imagenum] = True

    return result

def get_match():
    result = []
    with open(MATCHES_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            imagenum1 = int(row["imagenum1"])
            imagenum2 = int(row["imagenum2"])
            result.append({"name": name, "imagenum": imagenum1})
            result.append({"name": name, "imagenum": imagenum2})
    return result
            

def main():
    match = get_match()
    clear = get_clear()
    result = [m for m in match if clear.get(m["name"], {}).get(m["imagenum"]) is not None]
    with open(OUTPUT_FILENAME, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "imagenum"])
        writer.writeheader()
        writer.writerows(result)

if __name__ == "__main__":
    main()
    