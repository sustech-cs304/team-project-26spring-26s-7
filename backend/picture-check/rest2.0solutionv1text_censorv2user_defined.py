import requests

API_KEY = "9zmuVkEWX5F5o82vxaXV197W"
SECRET_KEY = "cmq4cDiX0gS7ZEHoaH7Q0OIFyQSKduCx"

def main():
        
    url = "https://aip.baidubce.com/rest/2.0/solution/v1/text_censor/v2/user_defined?access_token=" + get_access_token()
    
    payload='text=%E5%88%AB%E8%B7%9F%E8%80%81%E5%AD%90%E8%A3%85%E9%80%BC%EF%BC%8C%E4%BF%A1%E4%B8%8D%E4%BF%A1%E6%88%91%E4%B8%80%E5%B7%B4%E6%8E%8C%E5%91%BC%E6%AD%BB%E4%BD%A0%E3%80%82&strategyId=1'
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json'
    }
    
    response = requests.request("POST", url, headers=headers, data=payload.encode("utf-8"))
    
    response.encoding = "utf-8"
    print(response.text)
    

def get_access_token():
    """
    使用 AK，SK 生成鉴权签名（Access Token）
    :return: access_token，或是None(如果错误)
    """
    url = "https://aip.baidubce.com/oauth/2.0/token"
    params = {"grant_type": "client_credentials", "client_id": API_KEY, "client_secret": SECRET_KEY}
    return str(requests.post(url, params=params).json().get("access_token"))

if __name__ == '__main__':
    main()
