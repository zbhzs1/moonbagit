///|
test "metadata parser and writer reject terminal and NUL controls" {
  for control in ["\u0000", "\u001B", "\u007F", "\u000B"] {
    rejects(() => ignore(parse_metadata("Name: a" + control + "b\n")))
    rejects(() => ignore(parse_metadata("Na" + control + "me: value\n")))
    rejects(() => {
      ignore(render_metadata([{ label: "Name", value: "a" + control, }]))
    })
    rejects(() => {
      ignore(render_metadata([{ label: "Na" + control + "me", value: "a", }]))
    })
  }
}

///|
test "metadata writer refuses values that would lose continuation indentation" {
  for value in ["first\n second", "first\n\tsecond", "first\n ", "first\n\t"] {
    rejects(() => ignore(render_metadata([{ label: "Description", value, }])))
  }
}

///|
test "canonical metadata round trips empty lines Unicode tabs and initial spaces" {
  for
    value in [
      "", " initial space", "\tinitial tab", "first\nsecond", "first\n\nthird\n",
      "a\tb", "\u{4E2D}\u{6587}\nline",
    ] {
    let fields : Array[Metadata] = [{ label: "Description", value, }]
    assert_eq(parse_metadata(render_metadata(fields)), fields)
  }
}

///|
test "metadata continuation padding is syntax rather than content" {
  let fields = parse_metadata("Description: first\r\n \t  second\r\n")
  assert_eq(fields[0].value, "first\nsecond")
}

///|
test "metadata allows internal linear whitespace in labels" {
  let fields : Array[Metadata] = [
    { label: "Custom Field\tName", value: "value", },
  ]
  assert_eq(parse_metadata(render_metadata(fields)), fields)
}

///|
test "creation refuses unsafe metadata before producing tag text" {
  rejects(() => {
    ignore(
      create_tags([], metadata=[{ label: "Contact-Name", value: "\u001B[31m", }]),
    )
  })
  rejects(() => {
    ignore(
      create_tags([], metadata=[
        { label: "Description", value: "first\n hidden", },
      ]),
    )
  })
}
