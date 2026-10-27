import csv

INPUT_ALL_FILENAME = "all_buffalo_l.csv"
RESULT_FILENAME = "all_clear_buffalo_l.csv"

def get_succeeded_all():
    result = []
    with open(INPUT_ALL_FILENAME, newline="", encoding="utf-8") as infile:
        reader = csv.DictReader(infile)
        for row in reader:
            name = row["name"]
            imagenum = int(row["imagenum"])
            success = int(row["success"])
            if success == 1:
                result.append({"name": name, "imagenum": imagenum})
    return result

def main():
    result = get_succeeded_all()
    fieldnames = ["name", "imagenum"]
    with open(RESULT_FILENAME, "w", newline="", encoding="utf-8") as outfile:
        writer = csv.DictWriter(outfile, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(result)

if __name__ == "__main__":
    main()
