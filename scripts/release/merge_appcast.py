#!/usr/bin/env python3
"""Prepends a newly signed Appcast item onto the previously published Appcast.

Usage: merge_appcast.py <new-item-appcast.xml> <previous-appcast.xml-or-empty> <output.xml>

<previous-appcast.xml-or-empty> may point to a file that does not exist, in which case a
fresh Appcast is started with only the new item.
"""
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


def main() -> None:
    new_item_path, previous_path, output_path = sys.argv[1:4]

    ET.register_namespace("sparkle", SPARKLE_NS)

    new_root = ET.parse(new_item_path).getroot()
    new_item = new_root.find("./channel/item")
    if new_item is None:
        raise SystemExit(f"{new_item_path}: no <item> found")

    try:
        tree = ET.parse(previous_path)
        root = tree.getroot()
        channel = root.find("channel")
    except (FileNotFoundError, ET.ParseError):
        root = ET.Element("rss", {"version": "2.0"})
        channel = ET.SubElement(root, "channel")
        ET.SubElement(channel, "title").text = "cal-reminder"
        tree = ET.ElementTree(root)

    insert_at = next(
        (i for i, child in enumerate(channel) if child.tag == "item"),
        len(channel),
    )
    channel.insert(insert_at, new_item)
    tree.write(output_path, encoding="UTF-8", xml_declaration=True)


if __name__ == "__main__":
    main()
