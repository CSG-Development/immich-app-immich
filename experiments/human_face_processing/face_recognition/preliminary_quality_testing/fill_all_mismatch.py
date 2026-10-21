import csv

MISMATCHES_FILENAME = "mismatchpairsDevTrain_.csv"
CLEAR_FILENAME = "all_clear_buffalo_l.csv"
OUTPUT_FILENAME = "all_mismatch_buffalo_l.csv"

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

def get_mismatch():
    result = []
    with open(MISMATCHES_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name1 = row["name1"]
            imagenum1 = int(row["imagenum1"])
            name2 = row["name2"]
            imagenum2 = int(row["imagenum2"])
            result.append({"name": name1, "imagenum": imagenum1})
            result.append({"name": name2, "imagenum": imagenum2})
    return result
            

def main():
    mismatch = get_mismatch()
    clear = get_clear()
    result = [m for m in mismatch if clear.get(m["name"], {}).get(m["imagenum"]) is not None]
    with open(OUTPUT_FILENAME, mode="w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["name", "imagenum"])
        writer.writeheader()
        writer.writerows(result)

if __name__ == "__main__":
    main()
    