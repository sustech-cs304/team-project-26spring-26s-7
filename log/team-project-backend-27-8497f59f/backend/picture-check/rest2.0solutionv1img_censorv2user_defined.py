import requests

API_KEY = "9zmuVkEWX5F5o82vxaXV197W"
SECRET_KEY = "cmq4cDiX0gS7ZEHoaH7Q0OIFyQSKduCx"

def main():
        
    url = "https://aip.baidubce.com/rest/2.0/solution/v1/img_censor/v2/user_defined?access_token=" + get_access_token()
    
    payload='imgUrl=https%3A%2F%2Fbaidu-ai.bj.bcebos.com%2Fcensor%2Fimg_censor.jpeg&strategyId=1'
    headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
        'Authorization': 'Bearer '
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
