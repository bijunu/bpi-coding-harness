def validate_username(username):
    if not username:
        return False
    if username[0].isalpha():
        return True
    return False
